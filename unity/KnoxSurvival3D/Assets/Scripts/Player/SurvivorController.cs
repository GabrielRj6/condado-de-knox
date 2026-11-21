using System.Collections.Generic;
using FishNet.Object;
using FishNet.Object.Synchronizing;
using KnoxSurvival.Audio;
using KnoxSurvival.Networking;
using KnoxSurvival.Vehicles;
using KnoxSurvival.Zombies;
using UnityEngine;

namespace KnoxSurvival.Player
{
    /// <summary>
    /// Controle do Sobrevivente em 1a/3a Pessoa (FishNet v4) com combate sincronizado,
    /// som 3D direcional de disparos para todos os ouvintes e entrada em Carros/Motos (Piloto ou Garupa).
    /// </summary>
    [RequireComponent(typeof(CharacterController))]
    public class SurvivorController : NetworkBehaviour
    {
        public static readonly List<SurvivorController> AllSurvivors = new();
        public static SurvivorController LocalPlayer { get; private set; }

        [Header("Movimentacao")]
        public float walkSpeed = 4.6f;
        public float sprintSpeed = 7.4f;
        public float crouchSpeed = 2.6f;
        public float jumpSpeed = 5.4f;
        public float gravity = 18f;

        [Header("Camera (1P / 3P)")]
        public float mouseSensitivity = 2.0f;
        public float thirdPersonDistance = 3.2f;
        public Vector3 thirdPersonOffset = new Vector3(0.55f, 1.62f, 0f);
        public Vector3 firstPersonOffset = new Vector3(0f, 1.62f, 0.12f);

        [Header("Combate")]
        public WeaponSoundProfile activeWeaponSound = WeaponSoundProfile.Rifle;
        public float weaponDamage = 38f;
        public float fireCooldown = 0.12f;
        public float weaponRange = 220f;
        public Light flashlight;

        public readonly SyncVar<string> Nickname = new SyncVar<string>("Sobrevivente");
        public readonly SyncVar<string> TeamId = new SyncVar<string>("");
        public readonly SyncVar<int> Health = new SyncVar<int>(200);
        public readonly SyncVar<bool> IsDead = new SyncVar<bool>(false);
        public readonly SyncVar<bool> FlashlightOn = new SyncVar<bool>(false);

        public VehicleController3D CurrentVehicle { get; private set; }
        public int CurrentSeatIndex { get; private set; } = -1;

        private CharacterController _cc;
        private Camera _cam;
        private float _yaw;
        private float _pitch;
        private float _velY;
        private float _nextFireTime;
        private bool _firstPerson;
        private float _shoulderSign = 1f;

        private void Awake()
        {
            _cc = GetComponent<CharacterController>();
        }

        private void OnEnable()
        {
            if (!AllSurvivors.Contains(this)) AllSurvivors.Add(this);
        }

        private void OnDisable()
        {
            AllSurvivors.Remove(this);
            if (LocalPlayer == this) LocalPlayer = null;
        }

        public override void OnStartClient()
        {
            base.OnStartClient();
            FlashlightOn.OnChange += (_, next, _) =>
            {
                if (flashlight != null) flashlight.enabled = next;
            };

            if (base.IsOwner)
            {
                LocalPlayer = this;
                _cam = Camera.main;
                _yaw = transform.eulerAngles.y;

                if (RadminServerManager.Instance != null)
                {
                    CmdSyncIdentity(RadminServerManager.Instance.LocalNick, RadminServerManager.Instance.LocalTeamId);
                }
            }
        }

        private void Update()
        {
            if (!base.IsOwner) return;

            bool uiBlocked = RadminServerManager.Instance != null && RadminServerManager.Instance.MenuOpen;

            // Sincroniza troca de nick/time em tempo real caso o jogador edite no menu TAB
            if (RadminServerManager.Instance != null)
            {
                if (Nickname.Value != RadminServerManager.Instance.LocalNick || TeamId.Value != RadminServerManager.Instance.LocalTeamId)
                {
                    CmdSyncIdentity(RadminServerManager.Instance.LocalNick, RadminServerManager.Instance.LocalTeamId);
                }
            }

            if (!uiBlocked && !IsDead.Value)
            {
                HandleLook();
                HandleInteractions();

                if (CurrentVehicle == null)
                {
                    HandleMovement();
                    HandleCombat();
                }
                else
                {
                    // Garupa/passageiro (seat > 0) pode atirar do veiculo!
                    if (CurrentSeatIndex > 0) HandleCombat();
                    HandleVehicleKeys();
                }
            }

            UpdateCamera();
        }

        private void HandleLook()
        {
            float mx = Input.GetAxis("Mouse X") * mouseSensitivity;
            float my = Input.GetAxis("Mouse Y") * mouseSensitivity;
            _yaw += mx;
            _pitch = Mathf.Clamp(_pitch - my, -72f, 75f);

            if (Input.GetKeyDown(KeyCode.V)) _firstPerson = !_firstPerson;
            if (Input.GetKeyDown(KeyCode.Q)) _shoulderSign = -_shoulderSign;
            if (Input.GetKeyDown(KeyCode.F))
            {
                if (CurrentVehicle != null && CurrentSeatIndex == 0)
                    CurrentVehicle.CmdToggleHeadlights();
                else
                    CmdToggleFlashlight();
            }
        }

        private void HandleMovement()
        {
            transform.rotation = Quaternion.Euler(0f, _yaw, 0f);
            float h = Input.GetAxisRaw("Horizontal");
            float v = Input.GetAxisRaw("Vertical");
            bool crouch = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.C);
            bool sprint = Input.GetKey(KeyCode.LeftShift) && !crouch && v > 0.1f;

            float spd = crouch ? crouchSpeed : (sprint ? sprintSpeed : walkSpeed);
            Vector3 move = (transform.right * h + transform.forward * v).normalized * spd;

            if (_cc.isGrounded)
            {
                if (_velY < 0f) _velY = -2f;
                if (Input.GetKeyDown(KeyCode.Space) && !crouch) _velY = jumpSpeed;
            }
            _velY -= gravity * Time.deltaTime;
            move.y = _velY;

            _cc.Move(move * Time.deltaTime);
        }

        private void HandleCombat()
        {
            if (Input.GetMouseButton(0) && Time.time >= _nextFireTime && _cam != null)
            {
                _nextFireTime = Time.time + fireCooldown;
                Vector3 muzzle = _cam.transform.position + _cam.transform.forward * 0.55f + _cam.transform.right * 0.15f;
                Vector3 dir = _cam.transform.forward;
                CmdFireWeapon(muzzle, dir, (int)activeWeaponSound);
            }
        }

        private void HandleInteractions()
        {
            if (Input.GetKeyDown(KeyCode.E))
            {
                if (CurrentVehicle != null)
                {
                    CurrentVehicle.CmdExitVehicle(this);
                }
                else
                {
                    VehicleController3D nearest = FindNearestVehicle(4.2f);
                    if (nearest != null)
                    {
                        nearest.CmdEnterVehicle(this, preferPassenger: Input.GetKey(KeyCode.LeftShift));
                    }
                }
            }
        }

        private void HandleVehicleKeys()
        {
            if (CurrentVehicle == null) return;
            if (Input.GetKeyDown(KeyCode.G)) CurrentVehicle.CmdSwitchSeat(this);
            if (Input.GetKeyDown(KeyCode.H) && CurrentSeatIndex == 0) CurrentVehicle.CmdHonkHorn();
        }

        private void UpdateCamera()
        {
            if (_cam == null) return;

            if (CurrentVehicle != null)
            {
                Vector3 pivot = CurrentVehicle.transform.position + Vector3.up * (CurrentVehicle.isMotorcycle ? 1.45f : 1.75f);
                Quaternion rot = Quaternion.Euler(_pitch, _yaw, 0f);
                float dist = CurrentVehicle.isMotorcycle ? 4.4f : 5.8f;
                Vector3 desired = pivot - rot * Vector3.forward * dist;
                _cam.transform.SetPositionAndRotation(desired, rot);
                return;
            }

            Quaternion camRot = Quaternion.Euler(_pitch, _yaw, 0f);
            if (_firstPerson)
            {
                Vector3 pos = transform.position + transform.TransformDirection(firstPersonOffset);
                _cam.transform.SetPositionAndRotation(pos, camRot);
            }
            else
            {
                Vector3 pivot = transform.position + Vector3.up * thirdPersonOffset.y + transform.right * (thirdPersonOffset.x * _shoulderSign);
                Vector3 desired = pivot - camRot * Vector3.forward * thirdPersonDistance;
                if (Physics.Linecast(pivot, desired, out RaycastHit hit))
                    desired = hit.point + hit.normal * 0.18f;
                _cam.transform.SetPositionAndRotation(desired, camRot);
            }
        }

        private VehicleController3D FindNearestVehicle(float maxDist)
        {
            VehicleController3D best = null;
            float bestD = maxDist;
            foreach (var v in VehicleController3D.AllVehicles)
            {
                if (v == null || v.IsExploded.Value) continue;
                float d = Vector3.Distance(transform.position, v.transform.position);
                if (d < bestD)
                {
                    bestD = d;
                    best = v;
                }
            }
            return best;
        }

        public void AttachToVehicleSeat(VehicleController3D veh, int seatIndex)
        {
            CurrentVehicle = veh;
            CurrentSeatIndex = seatIndex;
            if (_cc != null) _cc.enabled = veh == null;
            if (veh != null)
            {
                Transform seatTf = veh.GetSeatTransform(seatIndex);
                transform.SetParent(seatTf, false);
                transform.localPosition = Vector3.zero;
                transform.localRotation = Quaternion.identity;
            }
            else
            {
                transform.SetParent(null, true);
            }
        }

        public void ApplyServerDamage(int dmg)
        {
            if (!base.IsServerInitialized || IsDead.Value) return;
            Health.Value = Mathf.Max(0, Health.Value - dmg);
            if (Health.Value <= 0)
            {
                IsDead.Value = true;
            }
        }

        [ServerRpc]
        private void CmdSyncIdentity(string nick, string team)
        {
            Nickname.Value = string.IsNullOrWhiteSpace(nick) ? "Sobrevivente" : nick.Trim();
            TeamId.Value = string.IsNullOrWhiteSpace(team) ? "" : team.Trim().ToUpperInvariant();
        }

        [ServerRpc]
        private void CmdToggleFlashlight()
        {
            FlashlightOn.Value = !FlashlightOn.Value;
        }

        [ServerRpc]
        private void CmdFireWeapon(Vector3 muzzlePos, Vector3 dir, int soundProfileIdx)
        {
            Vector3 normDir = dir.sqrMagnitude > 0.001f ? dir.normalized : transform.forward;
            Vector3 endPos = muzzlePos + normDir * weaponRange;

            if (Physics.Raycast(muzzlePos, normDir, out RaycastHit hit, weaponRange))
            {
                endPos = hit.point;
                var zombie = hit.collider.GetComponentInParent<ZombieAI>();
                if (zombie != null)
                {
                    bool head = hit.point.y > zombie.transform.position.y + 1.42f;
                    zombie.ApplyServerDamage(head ? weaponDamage * 3.2f : weaponDamage, normDir);
                }
                else
                {
                    var other = hit.collider.GetComponentInParent<SurvivorController>();
                    if (other != null && other != this)
                    {
                        bool sameTeam = !string.IsNullOrEmpty(TeamId.Value) && TeamId.Value == other.TeamId.Value;
                        if (!sameTeam) other.ApplyServerDamage(Mathf.RoundToInt(weaponDamage));
                    }
                }
            }

            // Alerta zumbis proximos no Servidor pelo barulho do tiro!
            float noiseRadius = (WeaponSoundProfile)soundProfileIdx == WeaponSoundProfile.Suppressed ? 24f : 115f;
            ZombieAI.AlertZombiesInRadius(muzzlePos, noiseRadius);

            // Reproduz som 3D direcional em TODOS os clientes (quem ouve escuta esquerda/direita/frente/tras + distancia!)
            RpcBroadcastShot(muzzlePos, endPos, soundProfileIdx);
        }

        [ObserversRpc]
        private void RpcBroadcastShot(Vector3 muzzlePos, Vector3 endPos, int soundProfileIdx)
        {
            if (SpatialAudio3D.Instance != null)
            {
                SpatialAudio3D.Instance.PlayGunshot3D((WeaponSoundProfile)soundProfileIdx, muzzlePos, endPos, base.IsOwner);
            }
            Debug.DrawLine(muzzlePos, endPos, Color.yellow, 0.08f);
        }
    }
}
