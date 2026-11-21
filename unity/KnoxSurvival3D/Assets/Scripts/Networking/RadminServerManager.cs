using System;
using System.Collections.Generic;
using FishNet;
using FishNet.Managing;
using FishNet.Object;
using FishNet.Object.Synchronizing;
using FishNet.Transporting;
using FishNet.Transporting.Tugboat;
using UnityEngine;

namespace KnoxSurvival.Networking
{
    /// <summary>
    /// Gerenciador de conexao Multiplayer via Radmin VPN (FishNet v4 + Tugboat UDP)
    /// com suporte a Host, Cliente, Servidor Dedicado (-dedicated), salvamento automatico
    /// do nome do sobrevivente e sincronizacao global de hora do dia e clima.
    /// </summary>
    public class RadminServerManager : NetworkBehaviour
    {
        public static RadminServerManager Instance { get; private set; }

        private const string PREF_NICK = "knox_survivor_nick";
        private const string PREF_LAST_IP = "knox_radmin_ip";
        private const string PREF_TEAM = "knox_team_id";

        [Header("Rede (Radmin VPN / UDP)")]
        public string defaultRadminIp = "127.0.0.1";
        public ushort port = 7777;

        [Header("Luz Solar Global (Sincronizada)")]
        public Light sunLight;

        [Header("Prefabs de Spawn")]
        public NetworkObject carPrefab;
        public NetworkObject motoTrailPrefab;
        public NetworkObject motoStreetPrefab;
        public NetworkObject zombiePrefab;

        public readonly SyncVar<float> TimeOfDayHours = new SyncVar<float>(11.5f);
        public readonly SyncVar<bool> StormMode = new SyncVar<bool>(false);
        public readonly SyncVar<double> MapLat = new SyncVar<double>(-23.5505);
        public readonly SyncVar<double> MapLng = new SyncVar<double>(-46.6333);
        public readonly SyncVar<float> MapAreaKm2 = new SyncVar<float>(1.0f);

        public string LocalNick { get; private set; } = "Sobrevivente";
        public string LocalTeamId { get; private set; } = "";
        public string TargetIp { get; private set; } = "127.0.0.1";
        public bool IsDedicatedServer { get; private set; }
        public bool MenuOpen { get; set; } = true;

        private string _statusMessage = "Pronto para conectar via Radmin VPN (UDP 7777)";
        private bool _showOnGui = true;

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }
            Instance = this;

            LocalNick = PlayerPrefs.GetString(PREF_NICK, "Sobrevivente");
            TargetIp = PlayerPrefs.GetString(PREF_LAST_IP, defaultRadminIp);
            LocalTeamId = PlayerPrefs.GetString(PREF_TEAM, "");

            TimeOfDayHours.OnChange += (_, _, _) => ApplyAtmosphereLighting();
            StormMode.OnChange += (_, _, _) => ApplyAtmosphereLighting();

            ParseCommandLineAndAutoStart();
        }

        private void Start()
        {
            ApplyAtmosphereLighting();
        }

        private void Update()
        {
            if (IsDedicatedServer) return;

            if (Input.GetKeyDown(KeyCode.Tab))
            {
                MenuOpen = !MenuOpen;
                Cursor.lockState = MenuOpen ? CursorLockMode.None : CursorLockMode.Locked;
                Cursor.visible = MenuOpen;
            }
        }

        public void SetLocalNick(string nick)
        {
            string clean = string.IsNullOrWhiteSpace(nick) ? "Sobrevivente" : nick.Trim();
            if (clean.Length > 18) clean = clean.Substring(0, 18);
            LocalNick = clean;
            PlayerPrefs.SetString(PREF_NICK, LocalNick);
            PlayerPrefs.Save();
        }

        public void SetLocalTeam(string teamId)
        {
            LocalTeamId = string.IsNullOrWhiteSpace(teamId) ? "" : teamId.Trim().ToUpperInvariant();
            PlayerPrefs.SetString(PREF_TEAM, LocalTeamId);
            PlayerPrefs.Save();
        }

        public void StartHost()
        {
            var nm = InstanceFinder.NetworkManager;
            if (nm == null) return;
            ConfigureTugboat(nm, "127.0.0.1", port);
            nm.ServerManager.StartConnection();
            nm.ClientManager.StartConnection();
            _statusMessage = $"HOST ATIVO NA PORTA UDP {port} — Passe seu IP do Radmin VPN (26.x.x.x) aos amigos.";
            MenuOpen = false;
            LockCursor();
        }

        public void StartClient(string ip)
        {
            var nm = InstanceFinder.NetworkManager;
            if (nm == null) return;
            TargetIp = string.IsNullOrWhiteSpace(ip) ? "127.0.0.1" : ip.Trim();
            PlayerPrefs.SetString(PREF_LAST_IP, TargetIp);
            PlayerPrefs.Save();

            ConfigureTugboat(nm, TargetIp, port);
            nm.ClientManager.StartConnection();
            _statusMessage = $"Conectando ao servidor Radmin {TargetIp}:{port}...";
            MenuOpen = false;
            LockCursor();
        }

        public void DisconnectClientOnly()
        {
            var nm = InstanceFinder.NetworkManager;
            if (nm == null) return;
            if (nm.IsClientStarted) nm.ClientManager.StopConnection();
            _statusMessage = "Desconectado da partida (se voce estiver rodando Servidor Dedicado, ele continua aberto!).";
            MenuOpen = true;
            UnlockCursor();
        }

        public void ShutdownServer()
        {
            var nm = InstanceFinder.NetworkManager;
            if (nm == null) return;
            if (nm.IsClientStarted) nm.ClientManager.StopConnection();
            if (nm.IsServerStarted) nm.ServerManager.StopConnection(true);
            _statusMessage = "Servidor encerrado.";
            MenuOpen = true;
            UnlockCursor();
        }

        [ServerRpc(RequireOwnership = false)]
        public void CmdSetTimeOfDay(float hours, bool storm)
        {
            TimeOfDayHours.Value = Mathf.Repeat(hours, 24f);
            StormMode.Value = storm;
        }

        [ServerRpc(RequireOwnership = false)]
        public void CmdSpawnZombiesAround(Vector3 center, int count)
        {
            if (zombiePrefab == null) return;
            int clamped = Mathf.Clamp(count, 1, 50);
            for (int i = 0; i < clamped; i++)
            {
                float ang = (i / (float)clamped) * Mathf.PI * 2f + UnityEngine.Random.Range(-0.2f, 0.2f);
                float rad = UnityEngine.Random.Range(14f, 34f);
                Vector3 pos = center + new Vector3(Mathf.Cos(ang) * rad, 0.2f, Mathf.Sin(ang) * rad);
                var nob = Instantiate(zombiePrefab, pos, Quaternion.Euler(0f, UnityEngine.Random.Range(0f, 360f), 0f));
                InstanceFinder.ServerManager.Spawn(nob);
            }
        }

        [ServerRpc(RequireOwnership = false)]
        public void CmdSpawnVehicle(Vector3 pos, Quaternion rot, int kind)
        {
            NetworkObject prefab = kind switch
            {
                1 => motoTrailPrefab,
                2 => motoStreetPrefab,
                _ => carPrefab
            };
            if (prefab == null) return;
            var nob = Instantiate(prefab, pos, rot);
            InstanceFinder.ServerManager.Spawn(nob);
        }

        private void ApplyAtmosphereLighting()
        {
            if (sunLight == null) sunLight = FindFirstObjectByType<Light>();
            if (sunLight == null) return;

            float h = TimeOfDayHours.Value;
            float sunElev = Mathf.Sin(((h - 6f) / 24f) * Mathf.PI * 2f);
            float pitch = Mathf.Lerp(-25f, 68f, Mathf.InverseLerp(-1f, 1f, sunElev));
            float yaw = (h / 24f) * 360f - 90f;
            sunLight.transform.rotation = Quaternion.Euler(pitch, yaw, 0f);

            bool isNight = sunElev < 0.05f;
            float stormMult = StormMode.Value ? 0.55f : 1f;
            sunLight.intensity = (isNight ? 0.14f : Mathf.Lerp(0.35f, 1.35f, Mathf.Clamp01(sunElev))) * stormMult;
            sunLight.color = isNight
                ? new Color(0.55f, 0.68f, 0.92f)
                : Color.Lerp(new Color(1f, 0.62f, 0.36f), new Color(1f, 0.97f, 0.90f), Mathf.Clamp01(sunElev * 2f));

            RenderSettings.ambientLight = isNight
                ? new Color(0.08f, 0.10f, 0.16f)
                : new Color(0.38f, 0.42f, 0.46f) * stormMult;
        }

        private void ParseCommandLineAndAutoStart()
        {
            string[] args = Environment.GetCommandLineArgs();
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i].Equals("-dedicated", StringComparison.OrdinalIgnoreCase))
                    IsDedicatedServer = true;
                else if (args[i].Equals("-port", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length && ushort.TryParse(args[i + 1], out ushort p))
                    port = p;
                else if (args[i].Equals("-lat", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length && double.TryParse(args[i + 1], System.Globalization.CultureInfo.InvariantCulture, out double lat))
                    MapLat.Value = lat;
                else if (args[i].Equals("-lng", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length && double.TryParse(args[i + 1], System.Globalization.CultureInfo.InvariantCulture, out double lng))
                    MapLng.Value = lng;
                else if (args[i].Equals("-area", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Length && float.TryParse(args[i + 1], System.Globalization.CultureInfo.InvariantCulture, out float area))
                    MapAreaKm2.Value = Mathf.Clamp(area, 0.5f, 4f);
            }

            if (IsDedicatedServer)
            {
                _showOnGui = false;
                MenuOpen = false;
                var nm = InstanceFinder.NetworkManager;
                if (nm != null)
                {
                    ConfigureTugboat(nm, "0.0.0.0", port);
                    nm.ServerManager.StartConnection();
                    Debug.Log($"[KnoxDedicated] Servidor Dedicado iniciado na porta UDP {port} (Radmin VPN pronto!)");
                }
            }
        }

        private static void ConfigureTugboat(NetworkManager nm, string clientIp, ushort udpPort)
        {
            if (nm.TransportManager.Transport is Tugboat tug)
            {
                tug.SetPort(udpPort);
                tug.SetClientAddress(clientIp);
                tug.SetServerBindAddress("0.0.0.0", IPAddressType.IPv4);
            }
        }

        private static void LockCursor()
        {
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
        }

        private static void UnlockCursor()
        {
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }

        private void OnGUI()
        {
            if (!_showOnGui || !MenuOpen) return;

            var nm = InstanceFinder.NetworkManager;
            bool isHost = nm != null && nm.IsServerStarted;
            bool isClient = nm != null && nm.IsClientStarted;

            GUILayout.BeginArea(new Rect(20, 20, 380, 470), "KNOX SURVIVAL 3D — RADMIN VPN", GUI.skin.window);

            GUILayout.Label("Nome do Sobrevivente (salvo automaticamente):");
            string nextNick = GUILayout.TextField(LocalNick, 18);
            if (nextNick != LocalNick) SetLocalNick(nextNick);

            GUILayout.Label("Codigo do Time / Party (so aliados do mesmo time aparecem no Mapa [M]):");
            string nextTeam = GUILayout.TextField(LocalTeamId, 12);
            if (nextTeam != LocalTeamId) SetLocalTeam(nextTeam);

            GUILayout.Space(8);
            GUILayout.Label("IP do Host no Radmin VPN (ex: 26.142.88.15 ou 127.0.0.1):");
            TargetIp = GUILayout.TextField(TargetIp, 32);

            GUILayout.Space(8);
            if (!isClient && !isHost)
            {
                if (GUILayout.Button("CRIAR SERVIDOR (HOST UDP 7777)", GUILayout.Height(34)))
                    StartHost();

                if (GUILayout.Button("ENTRAR NO SERVIDOR (RADMIN IP)", GUILayout.Height(34)))
                    StartClient(TargetIp);
            }
            else
            {
                if (GUILayout.Button("VOLTAR A PARTIDA [TAB]", GUILayout.Height(32)))
                {
                    MenuOpen = false;
                    LockCursor();
                }

                GUILayout.Space(6);
                GUILayout.Label($"Horario Global: {Mathf.FloorToInt(TimeOfDayHours.Value):00}:00");
                GUILayout.BeginHorizontal();
                if (GUILayout.Button("Dia (11h)")) CmdSetTimeOfDay(11f, false);
                if (GUILayout.Button("Tarde (17h)")) CmdSetTimeOfDay(17.5f, false);
                if (GUILayout.Button("Noite (22h)")) CmdSetTimeOfDay(22.5f, false);
                GUILayout.EndHorizontal();

                GUILayout.Space(6);
                GUILayout.Label("Acoes Rapidas (Sincronizado para TODOS):");
                if (Camera.main != null)
                {
                    Vector3 fwdPos = Camera.main.transform.position + Camera.main.transform.forward * 6f;
                    fwdPos.y = 0.5f;
                    GUILayout.BeginHorizontal();
                    if (GUILayout.Button("+ Carro")) CmdSpawnVehicle(fwdPos, Quaternion.identity, 0);
                    if (GUILayout.Button("+ Moto Trail")) CmdSpawnVehicle(fwdPos, Quaternion.identity, 1);
                    if (GUILayout.Button("+ Moto Street")) CmdSpawnVehicle(fwdPos, Quaternion.identity, 2);
                    GUILayout.EndHorizontal();
                    if (GUILayout.Button("+ Spawnar 10 Zumbis para Todos"))
                        CmdSpawnZombiesAround(Camera.main.transform.position, 10);
                }

                GUILayout.Space(8);
                if (GUILayout.Button("SAIR DA SALA (mantem Dedicado aberto)"))
                    DisconnectClientOnly();

                if (isHost && GUILayout.Button("ENCERRAR SERVIDOR"))
                    ShutdownServer();
            }

            GUILayout.Space(10);
            GUILayout.Label(_statusMessage);
            GUILayout.EndArea();
        }
    }
}
