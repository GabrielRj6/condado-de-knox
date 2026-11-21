using System.Collections.Generic;
using FishNet.Object;
using FishNet.Object.Synchronizing;
using KnoxSurvival.Audio;
using KnoxSurvival.Player;
using UnityEngine;

namespace KnoxSurvival.Vehicles
{
    public enum MotoStyle
    {
        None,
        Trail450,
        Street600
    }

    /// <summary>
    /// Fisica e rede para Carros (4 lugares) e Motos (Piloto + Garupa).
    /// Garante frenagem limpa ate 0 km/h (sem andar sozinho a 15 km/h),
    /// rodas alinhadas ao chao sem flutuar, inclinacao realista de moto e som 3D de motor/drift/buzina.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class VehicleController3D : NetworkBehaviour
    {
        public static readonly List<VehicleController3D> AllVehicles = new();

        [Header("Tipo de Veiculo")]
        public string vehicleLabel = "Knox Sedan '92";
        public bool isMotorcycle = false;
        public MotoStyle motoStyle = MotoStyle.None;
        public Transform visualBody;
        public Light[] headlights;

        [Header("Assentos (Carro: 4 | Moto: 0=Piloto, 1=Garupa)")]
        public Transform[] seatPivots;

        [Header("Fisica")]
        public float maxSpeedMps = 28f;
        public float reverseMaxSpeedMps = 8.5f;
        public float acceleration = 15f;
        public float brakeDeceleration = 30f;
        public float coastDrag = 5.5f;
        public float steerSpeedDeg = 95f;
        public float groundSnapOffset = 0.02f;

        public readonly SyncVar<float> SyncedSpeedMps = new SyncVar<float>(0f);
        public readonly SyncVar<float> SyncedSteer = new SyncVar<float>(0f);
        public readonly SyncVar<float> SyncedDrift = new SyncVar<float>(0f);
        public readonly SyncVar<bool> HasOccupant = new SyncVar<bool>(false);
        public readonly SyncVar<bool> LightsOn = new SyncVar<bool>(false);
        public readonly SyncVar<bool> IsExploded = new SyncVar<bool>(false);

        private Rigidbody _rb;
        private SurvivorController[] _occupants;
        private AudioSource _engineSrc;
        private AudioLowPassFilter _engineLpf;
        private AudioSource _driftSrc;

        private float _inputThrottle;
        private float _inputSteer;
        private bool _inputHandbrake;
        private float _forwardSpeed;

        private void Awake()
        {
            _rb = GetComponent<Rigidbody>();
            _rb.mass = isMotorcycle ? 210f : 1350f;
            _rb.centerOfMass = new Vector3(0f, isMotorcycle ? 0.35f : 0.45f, 0f);
            _rb.constraints = RigidbodyConstraints.FreezeRotationX | RigidbodyConstraints.FreezeRotationZ;

            int seatCount = Mathf.Max(isMotorcycle ? 2 : 4, seatPivots != null ? seatPivots.Length : 0);
            _occupants = new SurvivorController[seatCount];
        }

        private void OnEnable()
        {
            if (!AllVehicles.Contains(this)) AllVehicles.Add(this);
        }

        private void OnDisable()
        {
            AllVehicles.Remove(this);
        }

        private void Start()
        {
            Setup3DAudioSources();
            LightsOn.OnChange += (_, on, _) => ApplyHeadlights(on);
        }

        private void Setup3DAudioSources()
        {
            var engGo = new GameObject("EngineAudio3D");
            engGo.transform.SetParent(transform, false);
            engGo.transform.localPosition = new Vector3(0f, 0.7f, isMotorcycle ? 0.2f : 1.1f);
            _engineSrc = engGo.AddComponent<AudioSource>();
            _engineSrc.loop = true;
            _engineSrc.playOnAwake = false;
            _engineSrc.spatialBlend = 1f;
            _engineSrc.minDistance = 7f;
            _engineSrc.maxDistance = isMotorcycle ? 120f : 105f;
            _engineSrc.rolloffMode = AudioRolloffMode.Logarithmic;
            _engineSrc.volume = 0f;
            _engineLpf = engGo.AddComponent<AudioLowPassFilter>();
            _engineLpf.cutoffFrequency = 1800f;

            var drGo = new GameObject("DriftAudio3D");
            drGo.transform.SetParent(transform, false);
            drGo.transform.localPosition = new Vector3(0f, 0.25f, -0.8f);
            _driftSrc = drGo.AddComponent<AudioSource>();
            _driftSrc.loop = true;
            _driftSrc.playOnAwake = false;
            _driftSrc.spatialBlend = 1f;
            _driftSrc.minDistance = 6f;
            _driftSrc.maxDistance = 65f;
            _driftSrc.volume = 0f;
        }

        private void Update()
        {
            // Piloto local envia controles para o Servidor
            var driver = _occupants != null && _occupants.Length > 0 ? _occupants[0] : null;
            if (driver != null && driver.IsOwner)
            {
                bool uiBlocked = Networking.RadminServerManager.Instance != null && Networking.RadminServerManager.Instance.MenuOpen;
                float thr = uiBlocked ? 0f : Input.GetAxisRaw("Vertical");
                float str = uiBlocked ? 0f : Input.GetAxisRaw("Horizontal");
                bool hb = !uiBlocked && Input.GetKey(KeyCode.Space);
                CmdSendDriveInput(thr, str, hb);
            }

            UpdateVisualLeanAndSuspension();
            Update3DEngineAndDriftAudio();
        }

        private void FixedUpdate()
        {
            if (!base.IsServerInitialized || IsExploded.Value) return;

            bool hasDriver = _occupants[0] != null;
            float thr = hasDriver ? _inputThrottle : 0f;
            float str = hasDriver ? _inputSteer : 0f;
            bool hb = hasDriver && _inputHandbrake;

            // Frenagem limpa ate 0 km/h (nunca fica travado andando a 15 km/h!)
            if (hb)
            {
                _forwardSpeed = Mathf.MoveTowards(_forwardSpeed, 0f, brakeDeceleration * 1.45f * Time.fixedDeltaTime);
            }
            else if (thr > 0.05f)
            {
                if (_forwardSpeed < -0.2f)
                    _forwardSpeed = Mathf.MoveTowards(_forwardSpeed, 0f, brakeDeceleration * Time.fixedDeltaTime);
                else
                    _forwardSpeed = Mathf.MoveTowards(_forwardSpeed, maxSpeedMps, acceleration * thr * Time.fixedDeltaTime);
            }
            else if (thr < -0.05f)
            {
                if (_forwardSpeed > 0.2f)
                    _forwardSpeed = Mathf.MoveTowards(_forwardSpeed, 0f, brakeDeceleration * Time.fixedDeltaTime);
                else
                    _forwardSpeed = Mathf.MoveTowards(_forwardSpeed, -reverseMaxSpeedMps, (acceleration * 0.55f) * (-thr) * Time.fixedDeltaTime);
            }
            else
            {
                _forwardSpeed = Mathf.MoveTowards(_forwardSpeed, 0f, coastDrag * Time.fixedDeltaTime);
                if (Mathf.Abs(_forwardSpeed) < 0.08f) _forwardSpeed = 0f;
            }

            // Direcao proporcional a velocidade (moto gira mais agil)
            float spdFactor = Mathf.Clamp01(Mathf.Abs(_forwardSpeed) / 3.5f);
            float dirSign = _forwardSpeed >= 0f ? 1f : -1f;
            float turnDeg = str * steerSpeedDeg * spdFactor * dirSign * (hb ? 1.35f : 1f) * Time.fixedDeltaTime;
            _rb.MoveRotation(_rb.rotation * Quaternion.Euler(0f, turnDeg, 0f));

            // Alinha ao terreno (raycast no chao) para os pneus da moto/carro nunca flutuarem!
            Vector3 nextPos = _rb.position + transform.forward * (_forwardSpeed * Time.fixedDeltaTime);
            if (Physics.Raycast(nextPos + Vector3.up * 2.5f, Vector3.down, out RaycastHit hit, 6f, ~LayerMask.GetMask("Ignore Raycast")))
            {
                nextPos.y = hit.point.y + groundSnapOffset;
            }
            _rb.MovePosition(nextPos);

            SyncedSpeedMps.Value = _forwardSpeed;
            SyncedSteer.Value = Mathf.Lerp(SyncedSteer.Value, str, Time.fixedDeltaTime * 10f);
            SyncedDrift.Value = (hb && Mathf.Abs(_forwardSpeed) > 6f && Mathf.Abs(str) > 0.25f) ? 0.9f : 0f;
        }

        private void UpdateVisualLeanAndSuspension()
        {
            if (visualBody == null) return;
            float spd = SyncedSpeedMps.Value;
            float steer = SyncedSteer.Value;

            if (isMotorcycle)
            {
                // Moto deita PARA DENTRO da curva
                float leanDeg = Mathf.Clamp(-steer * Mathf.Clamp01(Mathf.Abs(spd) / 14f) * 26f, -28f, 28f);
                Quaternion target = Quaternion.Euler(0f, 0f, leanDeg);
                visualBody.localRotation = Quaternion.Slerp(visualBody.localRotation, target, Time.deltaTime * 10f);
            }
            else
            {
                float rollDeg = Mathf.Clamp(steer * Mathf.Clamp01(Mathf.Abs(spd) / 20f) * 5.5f, -7f, 7f);
                Quaternion target = Quaternion.Euler(0f, 0f, rollDeg);
                visualBody.localRotation = Quaternion.Slerp(visualBody.localRotation, target, Time.deltaTime * 10f);
            }
        }

        private void Update3DEngineAndDriftAudio()
        {
            if (_engineSrc == null || SpatialAudio3D.Instance == null) return;

            if (_engineSrc.clip == null)
            {
                _engineSrc.clip = SpatialAudio3D.Instance.GetEngineLoopClip(isMotorcycle, motoStyle == MotoStyle.Street600);
                if (_engineSrc.clip != null) _engineSrc.Play();
            }
            if (_driftSrc != null && _driftSrc.clip == null)
            {
                _driftSrc.clip = SpatialAudio3D.Instance.GetDriftLoopClip();
                if (_driftSrc.clip != null) _driftSrc.Play();
            }

            float absSpd = Mathf.Abs(SyncedSpeedMps.Value);
            bool active = !IsExploded.Value && (HasOccupant.Value || absSpd > 0.4f);

            if (!active)
            {
                _engineSrc.volume = Mathf.MoveTowards(_engineSrc.volume, 0f, Time.deltaTime * 3f);
                if (_driftSrc != null) _driftSrc.volume = 0f;
                return;
            }

            float speedNorm = Mathf.Clamp01(absSpd / Mathf.Max(1f, maxSpeedMps));
            float gears = isMotorcycle ? (motoStyle == MotoStyle.Street600 ? 6f : 5f) : 4f;
            float gearPos = (speedNorm * gears) % 1f;
            float rpmNorm = Mathf.Clamp01(0.18f + speedNorm * 0.55f + gearPos * 0.35f);

            float targetPitch = isMotorcycle
                ? (motoStyle == MotoStyle.Street600 ? Mathf.Lerp(0.85f, 2.35f, rpmNorm) : Mathf.Lerp(0.78f, 1.95f, rpmNorm))
                : Mathf.Lerp(0.72f, 1.80f, rpmNorm);

            _engineSrc.pitch = Mathf.Lerp(_engineSrc.pitch, targetPitch, Time.deltaTime * 10f);
            _engineSrc.volume = Mathf.Lerp(_engineSrc.volume, Mathf.Lerp(0.18f, 0.48f, rpmNorm), Time.deltaTime * 8f);
            if (_engineLpf != null)
            {
                _engineLpf.cutoffFrequency = Mathf.Lerp(650f, isMotorcycle ? 3600f : 2400f, rpmNorm);
            }

            if (_driftSrc != null)
            {
                _driftSrc.volume = Mathf.Lerp(_driftSrc.volume, SyncedDrift.Value * 0.25f, Time.deltaTime * 10f);
            }
        }

        public Transform GetSeatTransform(int seatIdx)
        {
            if (seatPivots != null && seatIdx >= 0 && seatIdx < seatPivots.Length && seatPivots[seatIdx] != null)
                return seatPivots[seatIdx];
            return transform;
        }

        private void ApplyHeadlights(bool on)
        {
            if (headlights == null) return;
            foreach (var l in headlights)
                if (l != null) l.enabled = on;
        }

        [ServerRpc(RequireOwnership = false)]
        public void CmdSendDriveInput(float throttle, float steer, bool handbrake)
        {
            _inputThrottle = Mathf.Clamp(throttle, -1f, 1f);
            _inputSteer = Mathf.Clamp(steer, -1f, 1f);
            _inputHandbrake = handbrake;
        }

        [ServerRpc(RequireOwnership = false)]
        public void CmdEnterVehicle(SurvivorController player, bool preferPassenger)
        {
            if (player == null || IsExploded.Value) return;
            int chosen = -1;
            if (preferPassenger)
            {
                for (int i = 1; i < _occupants.Length; i++)
                    if (_occupants[i] == null) { chosen = i; break; }
            }
            if (chosen < 0)
            {
                for (int i = 0; i < _occupants.Length; i++)
                    if (_occupants[i] == null) { chosen = i; break; }
            }
            if (chosen < 0) return;

            _occupants[chosen] = player;
            RefreshOccupiedFlag();
            RpcAssignSeat(player, chosen, true);
        }

        [ServerRpc(RequireOwnership = false)]
        public void CmdSwitchSeat(SurvivorController player)
        {
            if (player == null) return;
            int cur = System.Array.IndexOf(_occupants, player);
            if (cur < 0) return;

            for (int step = 1; step < _occupants.Length; step++)
            {
                int next = (cur + step) % _occupants.Length;
                if (_occupants[next] == null)
                {
                    _occupants[cur] = null;
                    _occupants[next] = player;
                    RpcAssignSeat(player, next, next == 0 && Mathf.Abs(_forwardSpeed) < 0.8f);
                    return;
                }
            }
        }

        [ServerRpc(RequireOwnership = false)]
        public void CmdExitVehicle(SurvivorController player)
        {
            if (player == null) return;
            int cur = System.Array.IndexOf(_occupants, player);
            if (cur < 0) return;

            _occupants[cur] = null;
            RefreshOccupiedFlag();
            Vector3 exitPos = transform.position + transform.right * (cur % 2 == 0 ? -1.8f : 1.8f) + Vector3.up * 0.25f;
            RpcDetachSeat(player, exitPos);
        }

        [ServerRpc(RequireOwnership = false)]
        public void CmdToggleHeadlights()
        {
            LightsOn.Value = !LightsOn.Value;
        }

        [ServerRpc(RequireOwnership = false)]
        public void CmdHonkHorn()
        {
            Zombies.ZombieAI.AlertZombiesInRadius(transform.position, 65f);
            RpcPlayHorn();
        }

        private void RefreshOccupiedFlag()
        {
            bool any = false;
            for (int i = 0; i < _occupants.Length; i++)
                if (_occupants[i] != null) { any = true; break; }
            HasOccupant.Value = any;
        }

        [ObserversRpc]
        private void RpcAssignSeat(SurvivorController player, int seatIdx, bool playStartSound)
        {
            if (player != null) player.AttachToVehicleSeat(this, seatIdx);
            if (playStartSound && seatIdx == 0 && SpatialAudio3D.Instance != null)
            {
                SpatialAudio3D.Instance.PlayEngineStart3D(isMotorcycle, transform.position);
            }
        }

        [ObserversRpc]
        private void RpcDetachSeat(SurvivorController player, Vector3 exitPos)
        {
            if (player != null)
            {
                player.AttachToVehicleSeat(null, -1);
                player.transform.position = exitPos;
            }
        }

        [ObserversRpc]
        private void RpcPlayHorn()
        {
            if (SpatialAudio3D.Instance != null)
            {
                SpatialAudio3D.Instance.PlayHorn3D(isMotorcycle, transform.position);
            }
        }
    }
}
