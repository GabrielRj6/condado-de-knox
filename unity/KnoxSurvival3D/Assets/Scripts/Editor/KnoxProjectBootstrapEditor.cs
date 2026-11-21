#if UNITY_EDITOR
using System.IO;
using FishNet.Component.Spawning;
using FishNet.Component.Transforming;
using FishNet.Managing;
using FishNet.Managing.Object;
using FishNet.Object;
using FishNet.Transporting.Tugboat;
using KnoxSurvival.Audio;
using KnoxSurvival.Networking;
using KnoxSurvival.Player;
using KnoxSurvival.UI;
using KnoxSurvival.Vehicles;
using KnoxSurvival.World;
using KnoxSurvival.Zombies;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace KnoxSurvival.EditorTools
{
    /// <summary>
    /// Auto-Setup em 1 clique no Unity Editor:
    /// Cria toda a cena jogavel, NetworkManager (FishNet + Tugboat UDP 7777),
    /// Prefabs (Sobrevivente, Carro, Moto Trail 450 com Piloto+Garupa, Moto Street 600, Zumbi),
    /// Audio 3D, Mapa Real OSM e Mapa Tatico [M].
    /// </summary>
    public static class KnoxProjectBootstrapEditor
    {
        private const string PrefabsDir = "Assets/Prefabs";
        private const string ScenesDir = "Assets/Scenes";

        [MenuItem("Knox Survival/1. Criar Cena Completa (Radmin + FishNet)")]
        public static void CreateCompleteSceneAndPrefabs()
        {
            Directory.CreateDirectory(PrefabsDir);
            Directory.CreateDirectory(ScenesDir);
            AssetDatabase.Refresh();

            var scene = EditorSceneManager.NewScene(NewSceneSetup.DefaultGameObjects, NewSceneMode.Single);

            // 1. Chao base 600x600m
            var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
            ground.name = "Ground_KnoxBase";
            ground.transform.localScale = new Vector3(60f, 1f, 60f);
            ground.GetComponent<Renderer>().sharedMaterial = CreateMat("Mat_Ground", new Color(0.20f, 0.24f, 0.18f));

            // 2. Cria Prefabs de Rede
            var playerPrefab = BuildSurvivorPrefab();
            var carPrefab = BuildVehiclePrefab("KnoxCar_Sedan", false, MotoStyle.None, new Color(0.22f, 0.30f, 0.42f));
            var motoTrailPrefab = BuildVehiclePrefab("KnoxMoto_Trail450", true, MotoStyle.Trail450, new Color(0.75f, 0.32f, 0.12f));
            var motoStreetPrefab = BuildVehiclePrefab("KnoxMoto_Street600", true, MotoStyle.Street600, new Color(0.14f, 0.16f, 0.20f));
            var zombiePrefab = BuildZombiePrefab();

            // 3. Registra prefabs no DefaultPrefabObjects do FishNet
            var prefabCollection = ScriptableObject.CreateInstance<DefaultPrefabObjects>();
            AssetDatabase.CreateAsset(prefabCollection, $"{PrefabsDir}/KnoxNetworkPrefabs.asset");
            prefabCollection.AddObject(playerPrefab);
            prefabCollection.AddObject(carPrefab);
            prefabCollection.AddObject(motoTrailPrefab);
            prefabCollection.AddObject(motoStreetPrefab);
            prefabCollection.AddObject(zombiePrefab);
            EditorUtility.SetDirty(prefabCollection);

            // 4. NetworkManager + Tugboat (UDP 7777 para Radmin VPN) + PlayerSpawner
            var nmGo = new GameObject("NetworkManager_FishNet");
            var nm = nmGo.AddComponent<NetworkManager>();
            var tug = nmGo.AddComponent<Tugboat>();
            tug.SetPort(7777);
            var spawner = nmGo.AddComponent<PlayerSpawner>();

            var nmSo = new SerializedObject(nm);
            var spawnProp = nmSo.FindProperty("_spawnablePrefabs");
            if (spawnProp != null) spawnProp.objectReferenceValue = prefabCollection;
            nmSo.ApplyModifiedPropertiesWithoutUndo();

            var spSo = new SerializedObject(spawner);
            var ppProp = spSo.FindProperty("_playerPrefab");
            if (ppProp != null) ppProp.objectReferenceValue = playerPrefab;
            spSo.ApplyModifiedPropertiesWithoutUndo();

            // 5. Gerenciadores de Cena (RadminServerManager, SpatialAudio3D, RealWorldMapLoader, TacticalFullMapUI)
            var sysGo = new GameObject("KnoxSystems_Root");
            sysGo.AddComponent<NetworkObject>();
            var radmin = sysGo.AddComponent<RadminServerManager>();
            radmin.sunLight = Object.FindFirstObjectByType<Light>();
            radmin.carPrefab = carPrefab;
            radmin.motoTrailPrefab = motoTrailPrefab;
            radmin.motoStreetPrefab = motoStreetPrefab;
            radmin.zombiePrefab = zombiePrefab;

            sysGo.AddComponent<SpatialAudio3D>();
            sysGo.AddComponent<RealWorldMapLoader>();
            sysGo.AddComponent<TacticalFullMapUI>();

            // 6. Salva cena e adiciona ao Build Settings
            string scenePath = $"{ScenesDir}/KnoxMain_Radmin.unity";
            EditorSceneManager.SaveScene(scene, scenePath);
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(scenePath, true) };
            AssetDatabase.SaveAssets();

            EditorUtility.DisplayDialog(
                "Knox Survival 3D Pronto!",
                "Cena 'KnoxMain_Radmin.unity' e todos os prefabs (Sobrevivente, Carro, Moto Trail 450, Moto Street 600 e Zumbi) foram criados!\n\n" +
                "Clique em PLAY para testar como Host ou conectar via IP do Radmin VPN (UDP 7777).",
                "Bora jogar!");
        }

        private static NetworkObject BuildSurvivorPrefab()
        {
            var go = new GameObject("Survivor_Player");
            var cc = go.AddComponent<CharacterController>();
            cc.height = 1.8f;
            cc.radius = 0.36f;
            cc.center = new Vector3(0f, 0.9f, 0f);

            var body = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            body.name = "BodyVisual";
            body.transform.SetParent(go.transform, false);
            body.transform.localPosition = new Vector3(0f, 0.95f, 0f);
            body.transform.localScale = new Vector3(0.65f, 0.9f, 0.65f);
            Object.DestroyImmediate(body.GetComponent<Collider>());
            body.GetComponent<Renderer>().sharedMaterial = CreateMat("Mat_Survivor", new Color(0.24f, 0.34f, 0.26f));

            var flashGo = new GameObject("Flashlight");
            flashGo.transform.SetParent(go.transform, false);
            flashGo.transform.localPosition = new Vector3(0.2f, 1.45f, 0.35f);
            var spot = flashGo.AddComponent<Light>();
            spot.type = LightType.Spot;
            spot.range = 32f;
            spot.spotAngle = 48f;
            spot.intensity = 6f;
            spot.enabled = false;

            var nob = go.AddComponent<NetworkObject>();
            go.AddComponent<NetworkTransform>();
            var ctrl = go.AddComponent<SurvivorController>();
            ctrl.flashlight = spot;

            return SaveAsNetworkPrefab(go, $"{PrefabsDir}/Survivor_Player.prefab");
        }

        private static NetworkObject BuildVehiclePrefab(string name, bool isMoto, MotoStyle style, Color col)
        {
            var go = new GameObject(name);
            var rb = go.AddComponent<Rigidbody>();
            rb.useGravity = true;
            rb.interpolation = RigidbodyInterpolation.Interpolate;

            var collider = go.AddComponent<BoxCollider>();
            collider.size = isMoto ? new Vector3(0.76f, 1.05f, 2.2f) : new Vector3(1.95f, 1.45f, 4.4f);
            collider.center = new Vector3(0f, collider.size.y * 0.5f, 0f);

            var bodyRoot = new GameObject("VisualBody");
            bodyRoot.transform.SetParent(go.transform, false);

            var chassis = GameObject.CreatePrimitive(PrimitiveType.Cube);
            chassis.name = "Chassis";
            chassis.transform.SetParent(bodyRoot.transform, false);
            chassis.transform.localPosition = new Vector3(0f, isMoto ? 0.62f : 0.72f, 0f);
            chassis.transform.localScale = isMoto ? new Vector3(0.48f, 0.48f, 1.9f) : new Vector3(1.9f, 0.9f, 4.3f);
            Object.DestroyImmediate(chassis.GetComponent<Collider>());
            chassis.GetComponent<Renderer>().sharedMaterial = CreateMat($"Mat_{name}", col);

            // Assentos: Moto tem Piloto (0) + Garupa (1) alinhados no banco sem afundar!
            int seatCount = isMoto ? 2 : 4;
            var seats = new Transform[seatCount];
            for (int i = 0; i < seatCount; i++)
            {
                var s = new GameObject(isMoto ? (i == 0 ? "Seat_Piloto" : "Seat_Garupa") : $"Seat_{i}");
                s.transform.SetParent(bodyRoot.transform, false);
                if (isMoto)
                {
                    s.transform.localPosition = i == 0 ? new Vector3(0f, 0.88f, -0.05f) : new Vector3(0f, 0.96f, -0.68f);
                }
                else
                {
                    float sx = (i % 2 == 0) ? -0.48f : 0.48f;
                    float sz = (i < 2) ? 0.35f : -0.65f;
                    s.transform.localPosition = new Vector3(sx, 0.55f, sz);
                }
                seats[i] = s.transform;
            }

            // Farol frontal
            var hlGo = new GameObject("Headlight");
            hlGo.transform.SetParent(bodyRoot.transform, false);
            hlGo.transform.localPosition = new Vector3(0f, 0.85f, isMoto ? 1.05f : 2.2f);
            var hl = hlGo.AddComponent<Light>();
            hl.type = LightType.Spot;
            hl.range = 42f;
            hl.spotAngle = 58f;
            hl.intensity = 10f;
            hl.enabled = false;

            go.AddComponent<NetworkObject>();
            go.AddComponent<NetworkTransform>();
            var vc = go.AddComponent<VehicleController3D>();
            vc.vehicleLabel = name;
            vc.isMotorcycle = isMoto;
            vc.motoStyle = style;
            vc.visualBody = bodyRoot.transform;
            vc.seatPivots = seats;
            vc.headlights = new[] { hl };
            vc.maxSpeedMps = isMoto ? (style == MotoStyle.Street600 ? 36f : 31f) : 28f;
            vc.steerSpeedDeg = isMoto ? 118f : 86f;

            return SaveAsNetworkPrefab(go, $"{PrefabsDir}/{name}.prefab");
        }

        private static NetworkObject BuildZombiePrefab()
        {
            var go = new GameObject("KnoxZombie");
            var col = go.AddComponent<CapsuleCollider>();
            col.height = 1.8f;
            col.radius = 0.38f;
            col.center = new Vector3(0f, 0.9f, 0f);

            var mesh = GameObject.CreatePrimitive(PrimitiveType.Capsule);
            mesh.name = "ZombieVisual";
            mesh.transform.SetParent(go.transform, false);
            mesh.transform.localPosition = new Vector3(0f, 0.95f, 0f);
            mesh.transform.localScale = new Vector3(0.65f, 0.92f, 0.65f);
            Object.DestroyImmediate(mesh.GetComponent<Collider>());
            mesh.GetComponent<Renderer>().sharedMaterial = CreateMat("Mat_Zombie", new Color(0.32f, 0.42f, 0.28f));

            go.AddComponent<NetworkObject>();
            go.AddComponent<NetworkTransform>();
            go.AddComponent<ZombieAI>();

            return SaveAsNetworkPrefab(go, $"{PrefabsDir}/KnoxZombie.prefab");
        }

        private static NetworkObject SaveAsNetworkPrefab(GameObject go, string path)
        {
            var prefab = PrefabUtility.SaveAsPrefabAsset(go, path);
            Object.DestroyImmediate(go);
            return prefab.GetComponent<NetworkObject>();
        }

        private static Material CreateMat(string name, Color col)
        {
            string matPath = $"{PrefabsDir}/{name}.mat";
            var existing = AssetDatabase.LoadAssetAtPath<Material>(matPath);
            if (existing != null) return existing;

            Shader sh = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
            var mat = new Material(sh) { color = col };
            AssetDatabase.CreateAsset(mat, matPath);
            return mat;
        }
    }
}
#endif
