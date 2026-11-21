using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using UnityEngine;
using UnityEngine.Networking;

namespace KnoxSurvival.World
{
    [Serializable]
    public class RoadSegmentData
    {
        public string name;
        public List<Vector3> points = new();
    }

    [Serializable]
    public class BuildingFootprintData
    {
        public Vector3 center;
        public Vector2 size;
        public float height;
    }

    /// <summary>
    /// Carregador assincrono de cidades reais via OpenStreetMap (Overpass API) direto no Unity.
    /// Gera ruas, predios com MeshCollider e o grafo de vias usado pela Rota GPS no Mapa [M].
    /// </summary>
    public class RealWorldMapLoader : MonoBehaviour
    {
        public static RealWorldMapLoader Instance { get; private set; }

        [Header("Coordenadas Iniciais (Ex: Av. Paulista, Sao Paulo)")]
        public double centerLat = -23.5614;
        public double centerLng = -46.6559;
        public float areaKm2 = 1.0f;
        public bool autoLoadOnStart = false;

        [Header("Materiais Opcionais")]
        public Material roadMaterial;
        public Material buildingMaterial;

        public readonly List<RoadSegmentData> Roads = new();
        public readonly List<BuildingFootprintData> Buildings = new();
        public bool IsLoading { get; private set; }
        public string LastStatus { get; private set; } = "Pronto";

        private Transform _worldRoot;

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }
            Instance = this;
        }

        private void Start()
        {
            if (autoLoadOnStart)
            {
                LoadArea(centerLat, centerLng, areaKm2);
            }
        }

        public void LoadArea(double lat, double lng, float km2)
        {
            if (IsLoading) return;
            centerLat = lat;
            centerLng = lng;
            areaKm2 = Mathf.Clamp(km2, 0.25f, 4f);
            StartCoroutine(FetchAndBuildCityRoutine(centerLat, centerLng, areaKm2));
        }

        private IEnumerator FetchAndBuildCityRoutine(double lat, double lng, float km2)
        {
            IsLoading = true;
            LastStatus = $"Baixando dados reais OSM ({lat:F4}, {lng:F4})...";

            float halfMeters = Mathf.Sqrt(km2) * 500f;
            double dLat = halfMeters / 111320.0;
            double dLng = halfMeters / (111320.0 * Math.Cos(lat * Math.PI / 180.0));

            string s = (lat - dLat).ToString("F6", CultureInfo.InvariantCulture);
            string w = (lng - dLng).ToString("F6", CultureInfo.InvariantCulture);
            string n = (lat + dLat).ToString("F6", CultureInfo.InvariantCulture);
            string e = (lng + dLng).ToString("F6", CultureInfo.InvariantCulture);

            string query = $"[out:json][timeout:20];(way[\"highway\"]({s},{w},{n},{e});way[\"building\"]({s},{w},{n},{e}););out body;>;out skel qt;";
            string url = "https://overpass-api.de/api/interpreter?data=" + UnityWebRequest.EscapeURL(query);

            using var req = UnityWebRequest.Get(url);
            req.timeout = 22;
            yield return req.SendWebRequest();

            if (req.result != UnityWebRequest.Result.Success)
            {
                LastStatus = $"Falha OSM ({req.error}) — gerando quarteiroes locais de fallback.";
                BuildFallbackCityGrid(halfMeters);
                IsLoading = false;
                yield break;
            }

            ParseOverpassMinimal(req.downloadHandler.text, lat, lng);
            BuildSceneGeometry();
            LastStatus = $"Mapa real carregado: {Roads.Count} ruas · {Buildings.Count} predios";
            IsLoading = false;
        }

        private void ClearWorld()
        {
            Roads.Clear();
            Buildings.Clear();
            if (_worldRoot != null) Destroy(_worldRoot.gameObject);
            _worldRoot = new GameObject("RealWorldCityRoot").transform;
            _worldRoot.SetParent(transform, false);
        }

        private void BuildFallbackCityGrid(float halfMeters)
        {
            ClearWorld();
            float span = Mathf.Min(halfMeters, 320f);
            float step = 64f;
            for (float x = -span; x <= span; x += step)
            {
                Roads.Add(new RoadSegmentData
                {
                    name = $"Av. Norte-Sul {x:F0}",
                    points = new List<Vector3> { new(x, 0.05f, -span), new(x, 0.05f, span) }
                });
            }
            for (float z = -span; z <= span; z += step)
            {
                Roads.Add(new RoadSegmentData
                {
                    name = $"Rua Leste-Oeste {z:F0}",
                    points = new List<Vector3> { new(-span, 0.05f, z), new(span, 0.05f, z) }
                });
            }
            var rng = new System.Random(1337);
            for (float x = -span + step * 0.5f; x < span; x += step)
            {
                for (float z = -span + step * 0.5f; z < span; z += step)
                {
                    if (Mathf.Abs(x) < 35f && Mathf.Abs(z) < 35f) continue;
                    Buildings.Add(new BuildingFootprintData
                    {
                        center = new Vector3(x, 0f, z),
                        size = new Vector2(rng.Next(14, 28), rng.Next(14, 28)),
                        height = rng.Next(7, 26)
                    });
                }
            }
            BuildSceneGeometry();
        }

        private void BuildSceneGeometry()
        {
            if (_worldRoot == null)
            {
                _worldRoot = new GameObject("RealWorldCityRoot").transform;
                _worldRoot.SetParent(transform, false);
            }

            Material rMat = roadMaterial != null ? roadMaterial : CreateSimpleMat(new Color(0.14f, 0.14f, 0.15f));
            Material bMat = buildingMaterial != null ? buildingMaterial : CreateSimpleMat(new Color(0.36f, 0.35f, 0.33f));

            // Ruas
            foreach (var road in Roads)
            {
                for (int i = 0; i < road.points.Count - 1; i++)
                {
                    Vector3 a = road.points[i];
                    Vector3 b = road.points[i + 1];
                    Vector3 diff = b - a;
                    float len = diff.magnitude;
                    if (len < 1f) continue;

                    var seg = GameObject.CreatePrimitive(PrimitiveType.Cube);
                    seg.name = "RoadSeg";
                    seg.transform.SetParent(_worldRoot, false);
                    seg.transform.position = (a + b) * 0.5f;
                    seg.transform.rotation = Quaternion.LookRotation(diff.normalized, Vector3.up);
                    seg.transform.localScale = new Vector3(7.5f, 0.08f, len + 0.4f);
                    seg.GetComponent<Renderer>().sharedMaterial = rMat;
                }
            }

            // Predios (em lote simples com BoxCollider nativo super leve)
            int maxB = Mathf.Min(Buildings.Count, 450);
            for (int i = 0; i < maxB; i++)
            {
                var bd = Buildings[i];
                var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
                go.name = $"Building_{i}";
                go.transform.SetParent(_worldRoot, false);
                go.transform.position = new Vector3(bd.center.x, bd.height * 0.5f, bd.center.z);
                go.transform.localScale = new Vector3(bd.size.x, bd.height, bd.size.y);
                go.GetComponent<Renderer>().sharedMaterial = bMat;
            }
        }

        /// <summary>
        /// Parser leve de Overpass JSON (sem depender de pacotes externos de JSON).
        /// </summary>
        private void ParseOverpassMinimal(string json, double originLat, double originLng)
        {
            ClearWorld();
            var nodes = new Dictionary<long, Vector3>();
            double cosLat = Math.Cos(originLat * Math.PI / 180.0);

            int idx = 0;
            while (idx < json.Length)
            {
                int typePos = json.IndexOf("\"type\":", idx, StringComparison.Ordinal);
                if (typePos < 0) break;
                int objStart = json.LastIndexOf('{', typePos);
                int objEnd = FindMatchingBrace(json, objStart);
                if (objStart < 0 || objEnd < 0) break;

                string chunk = json.Substring(objStart, objEnd - objStart + 1);
                idx = objEnd + 1;

                if (chunk.Contains("\"type\":\"node\"") || chunk.Contains("\"type\": \"node\""))
                {
                    if (TryExtractLong(chunk, "\"id\":", out long id) &&
                        TryExtractDouble(chunk, "\"lat\":", out double lat) &&
                        TryExtractDouble(chunk, "\"lon\":", out double lon))
                    {
                        float x = (float)((lon - originLng) * 111320.0 * cosLat);
                        float z = (float)((lat - originLat) * 111320.0);
                        nodes[id] = new Vector3(x, 0.05f, z);
                    }
                }
                else if (chunk.Contains("\"type\":\"way\"") || chunk.Contains("\"type\": \"way\""))
                {
                    bool isHighway = chunk.Contains("\"highway\"");
                    bool isBuilding = chunk.Contains("\"building\"");
                    if (!isHighway && !isBuilding) continue;

                    var pts = ExtractWayPoints(chunk, nodes);
                    if (pts.Count < 2) continue;

                    if (isHighway)
                    {
                        Roads.Add(new RoadSegmentData { name = "Via Real", points = pts });
                    }
                    else if (isBuilding && pts.Count >= 3)
                    {
                        float minX = float.MaxValue, maxX = float.MinValue, minZ = float.MaxValue, maxZ = float.MinValue;
                        foreach (var p in pts)
                        {
                            if (p.x < minX) minX = p.x;
                            if (p.x > maxX) maxX = p.x;
                            if (p.z < minZ) minZ = p.z;
                            if (p.z > maxZ) maxZ = p.z;
                        }
                        float sx = Mathf.Clamp(maxX - minX, 4f, 55f);
                        float sz = Mathf.Clamp(maxZ - minZ, 4f, 55f);
                        Buildings.Add(new BuildingFootprintData
                        {
                            center = new Vector3((minX + maxX) * 0.5f, 0f, (minZ + maxZ) * 0.5f),
                            size = new Vector2(sx, sz),
                            height = UnityEngine.Random.Range(7f, 22f)
                        });
                    }
                }
            }

            if (Roads.Count == 0 && Buildings.Count == 0)
            {
                BuildFallbackCityGrid(260f);
            }
        }

        private static int FindMatchingBrace(string s, int openIdx)
        {
            if (openIdx < 0 || openIdx >= s.Length) return -1;
            int depth = 0;
            bool inStr = false;
            for (int i = openIdx; i < s.Length; i++)
            {
                char c = s[i];
                if (c == '"' && (i == 0 || s[i - 1] != '\\')) inStr = !inStr;
                if (inStr) continue;
                if (c == '{') depth++;
                else if (c == '}') { depth--; if (depth == 0) return i; }
            }
            return -1;
        }

        private static bool TryExtractLong(string s, string key, out long val)
        {
            val = 0;
            int k = s.IndexOf(key, StringComparison.Ordinal);
            if (k < 0) return false;
            k += key.Length;
            while (k < s.Length && (s[k] == ' ' || s[k] == '\t')) k++;
            int end = k;
            while (end < s.Length && (char.IsDigit(s[end]) || s[end] == '-')) end++;
            return long.TryParse(s.Substring(k, end - k), out val);
        }

        private static bool TryExtractDouble(string s, string key, out double val)
        {
            val = 0;
            int k = s.IndexOf(key, StringComparison.Ordinal);
            if (k < 0) return false;
            k += key.Length;
            while (k < s.Length && (s[k] == ' ' || s[k] == '\t')) k++;
            int end = k;
            while (end < s.Length && (char.IsDigit(s[end]) || s[end] == '-' || s[end] == '.')) end++;
            return double.TryParse(s.Substring(k, end - k), NumberStyles.Float, CultureInfo.InvariantCulture, out val);
        }

        private static List<Vector3> ExtractWayPoints(string chunk, Dictionary<long, Vector3> nodes)
        {
            var list = new List<Vector3>();
            int k = chunk.IndexOf("\"nodes\":", StringComparison.Ordinal);
            if (k < 0) return list;
            int a = chunk.IndexOf('[', k);
            int b = chunk.IndexOf(']', a + 1);
            if (a < 0 || b < 0) return list;
            string[] ids = chunk.Substring(a + 1, b - a - 1).Split(',');
            foreach (var raw in ids)
            {
                if (long.TryParse(raw.Trim(), out long nid) && nodes.TryGetValue(nid, out Vector3 pt))
                {
                    list.Add(pt);
                }
            }
            return list;
        }

        private static Material CreateSimpleMat(Color c)
        {
            Shader sh = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
            var m = new Material(sh) { color = c };
            return m;
        }
    }
}
