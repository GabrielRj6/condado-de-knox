using System.Collections.Generic;
using KnoxSurvival.Networking;
using KnoxSurvival.Player;
using KnoxSurvival.World;
using UnityEngine;

namespace KnoxSurvival.UI
{
    /// <summary>
    /// Mapa Tatico Completo [M]:
    /// - Botoes de Zoom (+) e (-) + scroll do mouse
    /// - Clique para marcar locais no mapa
    /// - Rota GPS automatica quando o jogador esta em Carro ou Moto
    /// - Visibilidade ESTRITA por Time: jogadores so aparecem no mapa se forem do mesmo time!
    /// </summary>
    public class TacticalFullMapUI : MonoBehaviour
    {
        public bool IsOpen { get; private set; }

        private float _zoom = 1.0f;
        private Vector2 _centerWorld = Vector2.zero;
        private readonly List<Vector2> _markers = new();
        private bool _routeActive;
        private Texture2D _whiteTex;

        private void Awake()
        {
            _whiteTex = new Texture2D(1, 1);
            _whiteTex.SetPixel(0, 0, Color.white);
            _whiteTex.Apply();
        }

        private void Update()
        {
            if (Input.GetKeyDown(KeyCode.M))
            {
                IsOpen = !IsOpen;
                if (IsOpen && SurvivorController.LocalPlayer != null)
                {
                    Vector3 p = SurvivorController.LocalPlayer.transform.position;
                    _centerWorld = new Vector2(p.x, p.z);
                }
                Cursor.lockState = IsOpen ? CursorLockMode.None : CursorLockMode.Locked;
                Cursor.visible = IsOpen;
            }
        }

        public static bool ShouldShowPlayerOnMap(string localTeamId, string otherTeamId)
        {
            return !string.IsNullOrWhiteSpace(localTeamId)
                && !string.IsNullOrWhiteSpace(otherTeamId)
                && localTeamId.Trim().Equals(otherTeamId.Trim(), System.StringComparison.OrdinalIgnoreCase);
        }

        private void OnGUI()
        {
            if (!IsOpen) return;

            float w = Mathf.Min(Screen.width - 80f, 920f);
            float h = Mathf.Min(Screen.height - 80f, 640f);
            Rect box = new Rect((Screen.width - w) * 0.5f, (Screen.height - h) * 0.5f, w, h);

            GUI.Box(box, "MAPA TATICO COMPLETO [M] — CLIQUE P/ MARCAR LOCAL · SOMENTE ALIADOS DO MESMO TIME VISIVEIS");

            Rect mapRect = new Rect(box.x + 14f, box.y + 42f, box.width - 28f, box.height - 96f);
            DrawRect(mapRect, new Color(0.08f, 0.10f, 0.09f, 0.96f));

            float pixelsPerMeter = (mapRect.height / 360f) * _zoom;
            Vector2 mapCenterPx = mapRect.center;

            Vector2 WorldToMap(Vector2 wp)
            {
                float sx = mapCenterPx.x + (wp.x - _centerWorld.x) * pixelsPerMeter;
                float sy = mapCenterPx.y - (wp.y - _centerWorld.y) * pixelsPerMeter;
                return new Vector2(sx, sy);
            }

            Vector2 MapToWorld(Vector2 sp)
            {
                float wx = _centerWorld.x + (sp.x - mapCenterPx.x) / Mathf.Max(0.01f, pixelsPerMeter);
                float wz = _centerWorld.y - (sp.y - mapCenterPx.y) / Mathf.Max(0.01f, pixelsPerMeter);
                return new Vector2(wx, wz);
            }

            // Desenha ruas e predios carregados
            if (RealWorldMapLoader.Instance != null)
            {
                foreach (var b in RealWorldMapLoader.Instance.Buildings)
                {
                    Vector2 p = WorldToMap(new Vector2(b.center.x, b.center.z));
                    if (!mapRect.Contains(p)) continue;
                    float bw = Mathf.Max(2f, b.size.x * pixelsPerMeter);
                    float bh = Mathf.Max(2f, b.size.y * pixelsPerMeter);
                    DrawRect(new Rect(p.x - bw * 0.5f, p.y - bh * 0.5f, bw, bh), new Color(0.32f, 0.34f, 0.32f, 0.85f));
                }
                foreach (var r in RealWorldMapLoader.Instance.Roads)
                {
                    for (int i = 0; i < r.points.Count - 1; i++)
                    {
                        Vector2 a = WorldToMap(new Vector2(r.points[i].x, r.points[i].z));
                        Vector2 b = WorldToMap(new Vector2(r.points[i + 1].x, r.points[i + 1].z));
                        if (mapRect.Contains(a) || mapRect.Contains(b))
                            DrawLine(a, b, 2.2f, new Color(0.50f, 0.52f, 0.48f, 0.75f));
                    }
                }
            }

            // Rota GPS ativa para o ultimo marcador (quando em carro/moto ou ativada manualmente)
            var local = SurvivorController.LocalPlayer;
            if (local != null && _markers.Count > 0 && (_routeActive || local.CurrentVehicle != null))
            {
                Vector2 fromPx = WorldToMap(new Vector2(local.transform.position.x, local.transform.position.z));
                Vector2 toPx = WorldToMap(_markers[_markers.Count - 1]);
                DrawLine(fromPx, toPx, 3.2f, new Color(0.20f, 0.85f, 1f, 0.95f));
            }

            // Marcadores taticos
            for (int i = 0; i < _markers.Count; i++)
            {
                Vector2 mp = WorldToMap(_markers[i]);
                if (!mapRect.Contains(mp)) continue;
                DrawRect(new Rect(mp.x - 5f, mp.y - 5f, 10f, 10f), new Color(1f, 0.65f, 0.15f, 1f));
                GUI.Label(new Rect(mp.x + 7f, mp.y - 8f, 90f, 20f), $"PIN #{i + 1}");
            }

            // Jogador local + SOMENTE aliados do mesmo time!
            string localTeam = local != null ? local.TeamId.Value : "";
            foreach (var s in SurvivorController.AllSurvivors)
            {
                if (s == null) continue;
                bool isSelf = s == local;
                if (!isSelf && !ShouldShowPlayerOnMap(localTeam, s.TeamId.Value)) continue;

                Vector2 sp = WorldToMap(new Vector2(s.transform.position.x, s.transform.position.z));
                if (!mapRect.Contains(sp)) continue;
                Color col = isSelf ? new Color(1f, 0.90f, 0.25f) : new Color(0.42f, 0.95f, 0.45f);
                DrawRect(new Rect(sp.x - 5f, sp.y - 5f, 10f, 10f), col);
                GUI.Label(new Rect(sp.x + 8f, sp.y - 9f, 140f, 20f), isSelf ? $"{s.Nickname.Value} (VOCE)" : $"◆ {s.Nickname.Value}");
            }

            // Clique no mapa para adicionar marcador (Esq) ou remover ultimo (Dir)
            Event ev = Event.current;
            if (ev.type == EventType.MouseDown && mapRect.Contains(ev.mousePosition))
            {
                if (ev.button == 0)
                {
                    _markers.Add(MapToWorld(ev.mousePosition));
                    if (local != null && local.CurrentVehicle != null) _routeActive = true;
                    ev.Use();
                }
                else if (ev.button == 1 && _markers.Count > 0)
                {
                    _markers.RemoveAt(_markers.Count - 1);
                    ev.Use();
                }
            }
            else if (ev.type == EventType.ScrollWheel && mapRect.Contains(ev.mousePosition))
            {
                _zoom = Mathf.Clamp(_zoom * (ev.delta.y < 0 ? 1.18f : 0.85f), 0.35f, 6.0f);
                ev.Use();
            }

            // Barra inferior: Zoom (+) (-), Rota GPS, Limpar Marcadores, Centralizar
            float barY = box.yMax - 42f;
            if (GUI.Button(new Rect(box.x + 14f, barY, 44f, 30f), "−")) _zoom = Mathf.Clamp(_zoom / 1.28f, 0.35f, 6.0f);
            GUI.Label(new Rect(box.x + 64f, barY + 5f, 70f, 24f), $"{_zoom:F1}x");
            if (GUI.Button(new Rect(box.x + 122f, barY, 44f, 30f), "+")) _zoom = Mathf.Clamp(_zoom * 1.28f, 0.35f, 6.0f);

            if (GUI.Button(new Rect(box.x + 180f, barY, 155f, 30f), _routeActive ? "ROTA GPS: ATIVA" : "TRACAR ROTA GPS"))
                _routeActive = !_routeActive;

            if (GUI.Button(new Rect(box.x + 345f, barY, 130f, 30f), "LIMPAR PINS"))
            {
                _markers.Clear();
                _routeActive = false;
            }

            if (GUI.Button(new Rect(box.x + 485f, barY, 120f, 30f), "CENTRALIZAR") && local != null)
                _centerWorld = new Vector2(local.transform.position.x, local.transform.position.z);

            if (GUI.Button(new Rect(box.xMax - 114f, barY, 100f, 30f), "FECHAR [M]"))
            {
                IsOpen = false;
                Cursor.lockState = CursorLockMode.Locked;
                Cursor.visible = false;
            }
        }

        private void DrawRect(Rect r, Color c)
        {
            Color prev = GUI.color;
            GUI.color = c;
            GUI.DrawTexture(r, _whiteTex);
            GUI.color = prev;
        }

        private void DrawLine(Vector2 a, Vector2 b, float thickness, Color c)
        {
            Vector2 d = b - a;
            float len = d.magnitude;
            if (len < 0.5f) return;
            float angle = Mathf.Atan2(d.y, d.x) * Mathf.Rad2Deg;
            Matrix4x4 prevMat = GUI.matrix;
            Color prevCol = GUI.color;
            GUI.color = c;
            GUIUtility.RotateAroundPivot(angle, a);
            GUI.DrawTexture(new Rect(a.x, a.y - thickness * 0.5f, len, thickness), _whiteTex);
            GUI.matrix = prevMat;
            GUI.color = prevCol;
        }
    }
}
