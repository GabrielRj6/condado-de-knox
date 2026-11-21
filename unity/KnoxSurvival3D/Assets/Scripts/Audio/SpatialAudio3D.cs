using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace KnoxSurvival.Audio
{
    public enum WeaponSoundProfile
    {
        Pistol,
        Smg,
        Rifle,
        Shotgun,
        Sniper,
        Suppressed
    }

    public enum ZombieVocalType
    {
        Idle,
        Alert,
        Chase,
        Attack,
        Hurt,
        Death
    }

    /// <summary>
    /// Motor de Audio Espacial 3D para Unity (Tiros direcionais esquerda/direita/frente/tras,
    /// eco/distancia ate 500m, estalo supersonico de bala, motores de carro/moto e vozes de zumbis).
    /// Gera clips procedurais automaticamente caso nenhum AudioClip customizado seja atribuido no Inspector.
    /// </summary>
    public class SpatialAudio3D : MonoBehaviour
    {
        public static SpatialAudio3D Instance { get; private set; }

        [Header("Pool de Fontes 3D")]
        [SerializeField] private int oneShotPoolSize = 36;
        [SerializeField] private float speedOfSound = 343f;
        [SerializeField] private float maxGunshotDistance = 480f;

        [Header("Clips Opcionais (vazio = sintese procedural automatica)")]
        public AudioClip pistolClip;
        public AudioClip rifleClip;
        public AudioClip shotgunClip;
        public AudioClip sniperClip;
        public AudioClip suppressedClip;
        public AudioClip bulletWhizClip;
        public AudioClip explosionClip;
        public AudioClip carHornClip;
        public AudioClip motoHornClip;
        public AudioClip engineStartCarClip;
        public AudioClip engineStartMotoClip;
        public AudioClip zombieAlertClip;
        public AudioClip zombieIdleClip;
        public AudioClip zombieAttackClip;
        public AudioClip zombieDeathClip;

        private readonly List<PooledVoice> _pool = new();
        private int _poolCursor;
        private int _activeZombieVocals;
        private float _lastZombieVocalTime;

        private AudioClip _procCarLoop;
        private AudioClip _procTrailMotoLoop;
        private AudioClip _procStreetMotoLoop;
        private AudioClip _procDriftLoop;

        private class PooledVoice
        {
            public GameObject go;
            public AudioSource src;
            public AudioLowPassFilter lpf;
        }

        private void Awake()
        {
            if (Instance != null && Instance != this)
            {
                Destroy(gameObject);
                return;
            }
            Instance = this;
            DontDestroyOnLoad(gameObject);
            BuildProceduralFallbacks();
            InitPool();
        }

        private void InitPool()
        {
            for (int i = 0; i < oneShotPoolSize; i++)
            {
                var go = new GameObject($"SpatialVoice_{i}");
                go.transform.SetParent(transform, false);
                var src = go.AddComponent<AudioSource>();
                src.playOnAwake = false;
                src.spatialBlend = 1f;
                src.dopplerLevel = 0.2f;
                src.rolloffMode = AudioRolloffMode.Custom;
                src.minDistance = 8f;
                src.maxDistance = maxGunshotDistance;
                src.spread = 0f;

                var lpf = go.AddComponent<AudioLowPassFilter>();
                lpf.cutoffFrequency = 18000f;
                lpf.lowpassResonanceQ = 1f;

                _pool.Add(new PooledVoice { go = go, src = src, lpf = lpf });
            }
        }

        private PooledVoice NextVoice()
        {
            var v = _pool[_poolCursor];
            _poolCursor = (_poolCursor + 1) % _pool.Count;
            return v;
        }

        /// <summary>
        /// Calcula atenuacao, filtro traseiro (frente vs. tras) e atraso da velocidade do som.
        /// </summary>
        public void ComputeAcoustics(
            Vector3 sourcePos,
            float refDist,
            float maxDist,
            float rolloff,
            float minLowpass,
            out float dist,
            out float gain,
            out float lowpassHz,
            out float delaySec)
        {
            var listener = Camera.main != null ? Camera.main.transform : transform;
            Vector3 toSrc = sourcePos - listener.position;
            dist = toSrc.magnitude;

            if (dist >= maxDist)
            {
                gain = 0f;
                lowpassHz = minLowpass;
                delaySec = 0f;
                return;
            }

            Vector3 dir = dist > 0.001f ? toSrc / dist : listener.forward;
            float frontDot = Vector3.Dot(dir, listener.forward); // +1 frente, -1 tras

            float eff = Mathf.Max(refDist, dist);
            float inv = Mathf.Pow(refDist / eff, rolloff);
            float edge = Mathf.Clamp01(1f - Mathf.Pow(dist / maxDist, 2.2f));
            // Leve queda atras da cabeca (sombra acustica da orelha)
            float rearGain = frontDot < 0f ? 1f + frontDot * 0.14f : 1f;
            gain = Mathf.Clamp01(inv * edge * rearGain);

            // Escurecimento atmosferico pela distancia + filtro pinna traseiro (diferencia frente x tras claramente!)
            float distNorm = Mathf.Clamp01(dist / maxDist);
            float distLpf = Mathf.Lerp(17500f, minLowpass, Mathf.Pow(distNorm, 0.72f));
            float rearLpfMult = frontDot < 0f ? Mathf.Lerp(1f, 0.42f, -frontDot) : 1f;
            lowpassHz = Mathf.Clamp(distLpf * rearLpfMult, minLowpass, 18000f);

            delaySec = dist / speedOfSound;
        }

        /// <summary>
        /// Reproduz tiro 3D direcional: forte e seco de perto, suave/abafado/com eco de longe, sempre na direcao exata.
        /// Tambem dispara estalo supersonico se a bala passar perto do ouvinte.
        /// </summary>
        public void PlayGunshot3D(WeaponSoundProfile profile, Vector3 muzzlePos, Vector3 endPos, bool isLocalShooter)
        {
            AudioClip clip = profile switch
            {
                WeaponSoundProfile.Pistol => pistolClip,
                WeaponSoundProfile.Shotgun => shotgunClip,
                WeaponSoundProfile.Sniper => sniperClip,
                WeaponSoundProfile.Suppressed => suppressedClip,
                _ => rifleClip
            };
            if (clip == null) return;

            if (isLocalShooter)
            {
                var v = NextVoice();
                v.go.transform.position = muzzlePos;
                v.src.spatialBlend = 0.2f;
                v.src.volume = profile == WeaponSoundProfile.Suppressed ? 0.45f : 0.88f;
                v.src.pitch = UnityEngine.Random.Range(0.96f, 1.04f);
                v.lpf.cutoffFrequency = 18000f;
                v.src.clip = clip;
                v.src.Play();
                return;
            }

            float maxD = profile == WeaponSoundProfile.Suppressed ? 135f : (profile == WeaponSoundProfile.Sniper ? 520f : maxGunshotDistance);
            float refD = profile == WeaponSoundProfile.Suppressed ? 8f : 16f;
            ComputeAcoustics(muzzlePos, refD, maxD, profile == WeaponSoundProfile.Suppressed ? 1.8f : 1.1f, 820f,
                out float dist, out float gain, out float lowpassHz, out float delaySec);

            if (gain <= 0.006f) return;

            // Toca o tiro com atraso fisico real da velocidade do som
            StartCoroutine(PlayDelayedSpatial(clip, muzzlePos, gain, lowpassHz,
                UnityEngine.Random.Range(0.95f, 1.05f), Mathf.Min(delaySec, 1.4f)));

            // Verifica se a trajetoria do projetil passou perto da camera -> estalo supersonico direcional!
            if (profile != WeaponSoundProfile.Suppressed && dist > 10f && Camera.main != null && bulletWhizClip != null)
            {
                Vector3 lp = Camera.main.transform.position;
                Vector3 ab = endPos - muzzlePos;
                float len2 = ab.sqrMagnitude;
                if (len2 > 4f)
                {
                    float t = Mathf.Clamp01(Vector3.Dot(lp - muzzlePos, ab) / len2);
                    Vector3 closest = muzzlePos + ab * t;
                    float passDist = Vector3.Distance(lp, closest);
                    if (passDist < 12.5f && t > 0.05f)
                    {
                        float whizVol = Mathf.Clamp01(1f - passDist / 12.5f) * 0.72f;
                        StartCoroutine(PlayDelayedSpatial(bulletWhizClip, closest, whizVol, 12000f,
                            UnityEngine.Random.Range(0.92f, 1.12f), 0.01f));
                    }
                }
            }
        }

        public void PlayZombieVocal3D(ZombieVocalType type, Vector3 worldPos, float pitchVar = 1f)
        {
            bool urgent = type is ZombieVocalType.Alert or ZombieVocalType.Attack or ZombieVocalType.Hurt or ZombieVocalType.Death;
            if (_activeZombieVocals >= (urgent ? 6 : 4)) return;
            if (!urgent && Time.time - _lastZombieVocalTime < 0.28f) return;

            float maxD = type is ZombieVocalType.Alert or ZombieVocalType.Death ? 55f : 38f;
            ComputeAcoustics(worldPos, 5.5f, maxD, 1.5f, 620f, out _, out float gain, out float lowpassHz, out _);
            if (gain <= 0.015f) return;

            AudioClip clip = type switch
            {
                ZombieVocalType.Alert => zombieAlertClip,
                ZombieVocalType.Attack => zombieAttackClip,
                ZombieVocalType.Death => zombieDeathClip,
                _ => zombieIdleClip
            };
            if (clip == null) return;

            _activeZombieVocals++;
            _lastZombieVocalTime = Time.time;

            var v = NextVoice();
            v.go.transform.position = worldPos + Vector3.up * 1.4f;
            v.src.spatialBlend = 1f;
            v.src.minDistance = 4f;
            v.src.maxDistance = maxD;
            v.src.volume = gain * (urgent ? 0.85f : 0.55f);
            v.src.pitch = Mathf.Clamp(pitchVar * UnityEngine.Random.Range(0.94f, 1.06f), 0.72f, 1.32f);
            v.lpf.cutoffFrequency = lowpassHz;
            v.src.clip = clip;
            v.src.Play();
            StartCoroutine(ReleaseZombieVoiceAfter(clip.length / Mathf.Max(0.5f, v.src.pitch)));
        }

        public void PlayHorn3D(bool isMoto, Vector3 worldPos)
        {
            AudioClip clip = isMoto ? motoHornClip : carHornClip;
            if (clip == null) return;
            ComputeAcoustics(worldPos, 12f, 150f, 1.3f, 700f, out _, out float gain, out float lpf, out float delay);
            if (gain <= 0.01f) return;
            StartCoroutine(PlayDelayedSpatial(clip, worldPos, gain * 0.78f, lpf, 1f, Mathf.Min(delay, 0.45f)));
        }

        public void PlayEngineStart3D(bool isMoto, Vector3 worldPos)
        {
            AudioClip clip = isMoto ? engineStartMotoClip : engineStartCarClip;
            if (clip == null) return;
            ComputeAcoustics(worldPos, 6f, 55f, 1.5f, 750f, out _, out float gain, out float lpf, out _);
            if (gain <= 0.01f) return;
            StartCoroutine(PlayDelayedSpatial(clip, worldPos, gain * 0.65f, lpf, 1f, 0f));
        }

        public void PlayExplosion3D(Vector3 worldPos)
        {
            if (explosionClip == null) return;
            ComputeAcoustics(worldPos, 24f, 520f, 1.05f, 520f, out _, out float gain, out float lpf, out float delay);
            if (gain <= 0.01f) return;
            StartCoroutine(PlayDelayedSpatial(explosionClip, worldPos, gain, lpf, 1f, Mathf.Min(delay, 1.5f)));
        }

        public AudioClip GetEngineLoopClip(bool isMoto, bool isStreetMoto)
        {
            if (!isMoto) return _procCarLoop;
            return isStreetMoto ? _procStreetMotoLoop : _procTrailMotoLoop;
        }

        public AudioClip GetDriftLoopClip() => _procDriftLoop;

        private IEnumerator PlayDelayedSpatial(AudioClip clip, Vector3 pos, float gain, float lpfHz, float pitch, float delay)
        {
            if (delay > 0.005f) yield return new WaitForSeconds(delay);
            var v = NextVoice();
            v.go.transform.position = pos;
            v.src.spatialBlend = 1f;
            v.src.minDistance = maxGunshotDistance; // evita dupla atenuacao: gain ja foi calculado por ComputeAcoustics!
            v.src.maxDistance = maxGunshotDistance + 1f;
            v.src.volume = Mathf.Clamp01(gain);
            v.src.pitch = pitch;
            v.lpf.cutoffFrequency = lpfHz;
            v.src.clip = clip;
            v.src.Play();
        }

        private IEnumerator ReleaseZombieVoiceAfter(float sec)
        {
            yield return new WaitForSeconds(Mathf.Max(0.15f, sec));
            _activeZombieVocals = Mathf.Max(0, _activeZombieVocals - 1);
        }

        // =========================================================================
        // SINTESE PROCEDURAL DE FALLBACK (funciona sem precisar importar .wav!)
        // =========================================================================
        private void BuildProceduralFallbacks()
        {
            if (pistolClip == null) pistolClip = CreateGunshotClip(175f, 0.38f, 0.78f);
            if (rifleClip == null) rifleClip = CreateGunshotClip(140f, 0.56f, 0.92f);
            if (shotgunClip == null) shotgunClip = CreateGunshotClip(98f, 0.72f, 1.0f);
            if (sniperClip == null) sniperClip = CreateGunshotClip(84f, 0.95f, 1.0f);
            if (suppressedClip == null) suppressedClip = CreateGunshotClip(320f, 0.14f, 0.48f);
            if (bulletWhizClip == null) bulletWhizClip = CreateWhizClip();
            if (explosionClip == null) explosionClip = CreateExplosionClip();
            if (carHornClip == null) carHornClip = CreateDualToneClip(392f, 493.88f, 0.45f, 0.45f);
            if (motoHornClip == null) motoHornClip = CreateDualToneClip(587f, 660f, 0.30f, 0.42f);
            if (engineStartCarClip == null) engineStartCarClip = CreateStarterClip(false);
            if (engineStartMotoClip == null) engineStartMotoClip = CreateStarterClip(true);
            if (zombieIdleClip == null) zombieIdleClip = CreateZombieClip(86f, 64f, 0.70f);
            if (zombieAlertClip == null) zombieAlertClip = CreateZombieClip(152f, 94f, 0.62f);
            if (zombieAttackClip == null) zombieAttackClip = CreateZombieClip(182f, 78f, 0.34f);
            if (zombieDeathClip == null) zombieDeathClip = CreateZombieClip(118f, 42f, 0.88f);

            _procCarLoop = CreateEngineLoopClip(55f, 110f, 0.28f, 8f);
            _procTrailMotoLoop = CreateEngineLoopClip(72f, 144f, 0.38f, 14f);
            _procStreetMotoLoop = CreateEngineLoopClip(125f, 250f, 0.22f, 26f);
            _procDriftLoop = CreateNoiseLoopClip(0.8f);
        }

        private static AudioClip CreateGunshotClip(float baseHz, float dur, float punch)
        {
            const int sr = 44100;
            int len = Mathf.CeilToInt(sr * dur);
            var data = new float[len];
            var rng = new System.Random((int)(baseHz * 100));
            float phase = 0f;
            float lp = 0f;

            for (int i = 0; i < len; i++)
            {
                float t = i / (float)sr;
                float f = Mathf.Lerp(baseHz, 26f, Mathf.Min(1f, t / 0.14f));
                phase += 2f * Mathf.PI * f / sr;
                float thump = Mathf.Sin(phase) * Mathf.Exp(-t * 16f) * punch;
                float noise = (float)(rng.NextDouble() * 2.0 - 1.0);
                float crack = noise * Mathf.Exp(-t * 28f) * 0.9f;
                lp = Mathf.Lerp(lp, noise, 0.08f);
                float tail = lp * Mathf.Exp(-t * (2.6f / Mathf.Max(0.2f, dur))) * 0.42f;
                data[i] = Mathf.Clamp(thump + crack + tail, -1f, 1f);
            }

            var clip = AudioClip.Create($"ProcGun_{baseHz}", len, 1, sr, false);
            clip.SetData(data, 0);
            return clip;
        }

        private static AudioClip CreateWhizClip()
        {
            const int sr = 44100;
            int len = (int)(sr * 0.16f);
            var data = new float[len];
            var rng = new System.Random(77);
            float phase = 0f;
            for (int i = 0; i < len; i++)
            {
                float t = i / (float)sr;
                float f = Mathf.Lerp(2600f, 420f, t / 0.16f);
                phase += 2f * Mathf.PI * f / sr;
                float env = Mathf.Sin(Mathf.PI * (t / 0.16f));
                float n = (float)(rng.NextDouble() * 2.0 - 1.0) * 0.35f;
                data[i] = Mathf.Clamp((Mathf.Sin(phase) * 0.65f + n) * env, -1f, 1f);
            }
            var clip = AudioClip.Create("ProcWhiz", len, 1, sr, false);
            clip.SetData(data, 0);
            return clip;
        }

        private static AudioClip CreateExplosionClip()
        {
            const int sr = 44100;
            int len = (int)(sr * 1.45f);
            var data = new float[len];
            var rng = new System.Random(999);
            float phase = 0f, lp = 0f;
            for (int i = 0; i < len; i++)
            {
                float t = i / (float)sr;
                float f = Mathf.Lerp(78f, 18f, Mathf.Min(1f, t / 0.85f));
                phase += 2f * Mathf.PI * f / sr;
                float n = (float)(rng.NextDouble() * 2.0 - 1.0);
                lp = Mathf.Lerp(lp, n, 0.045f);
                data[i] = Mathf.Clamp(Mathf.Sin(phase) * Mathf.Exp(-t * 2.5f) * 0.9f + lp * Mathf.Exp(-t * 2.1f) * 1.1f, -1f, 1f);
            }
            var clip = AudioClip.Create("ProcExplosion", len, 1, sr, false);
            clip.SetData(data, 0);
            return clip;
        }

        private static AudioClip CreateDualToneClip(float f1, float f2, float dur, float vol)
        {
            const int sr = 44100;
            int len = (int)(sr * dur);
            var data = new float[len];
            for (int i = 0; i < len; i++)
            {
                float t = i / (float)sr;
                float env = Mathf.Min(1f, t / 0.02f) * Mathf.Clamp01((dur - t) / 0.06f);
                float s1 = Mathf.Sign(Mathf.Sin(2f * Mathf.PI * f1 * t)) * 0.5f;
                float s2 = Mathf.Sign(Mathf.Sin(2f * Mathf.PI * f2 * t)) * 0.5f;
                data[i] = (s1 + s2) * 0.5f * vol * env;
            }
            var clip = AudioClip.Create($"ProcHorn_{f1}", len, 1, sr, false);
            clip.SetData(data, 0);
            return clip;
        }

        private static AudioClip CreateStarterClip(bool isMoto)
        {
            const int sr = 44100;
            float dur = isMoto ? 0.36f : 0.48f;
            int len = (int)(sr * dur);
            var data = new float[len];
            float phase = 0f;
            for (int i = 0; i < len; i++)
            {
                float t = i / (float)sr;
                float f = isMoto ? Mathf.Lerp(82f, 220f, t / dur) : Mathf.Lerp(42f, 118f, t / dur);
                phase += 2f * Mathf.PI * f / sr;
                float crank = 0.55f + 0.45f * Mathf.Sin(2f * Mathf.PI * (isMoto ? 18f : 11f) * t);
                float env = Mathf.Sin(Mathf.PI * (t / dur));
                data[i] = Mathf.Clamp(Mathf.Sin(phase) * crank * env * 0.65f, -1f, 1f);
            }
            var clip = AudioClip.Create(isMoto ? "ProcStartMoto" : "ProcStartCar", len, 1, sr, false);
            clip.SetData(data, 0);
            return clip;
        }

        private static AudioClip CreateZombieClip(float fStart, float fEnd, float dur)
        {
            const int sr = 44100;
            int len = (int)(sr * dur);
            var data = new float[len];
            var rng = new System.Random((int)(fStart * 31));
            float phase = 0f, lp = 0f;
            for (int i = 0; i < len; i++)
            {
                float t = i / (float)sr;
                float u = t / dur;
                float vib = Mathf.Sin(2f * Mathf.PI * 22f * t) * 9f;
                float f = Mathf.Lerp(fStart, fEnd, u) + vib;
                phase += 2f * Mathf.PI * f / sr;
                float saw = (phase / Mathf.PI) % 2f - 1f;
                float rasp = (float)(rng.NextDouble() * 2.0 - 1.0) * 0.35f;
                lp = Mathf.Lerp(lp, saw * 0.65f + rasp, 0.14f);
                float env = Mathf.Min(1f, u / 0.18f) * Mathf.Clamp01((1f - u) / 0.25f);
                data[i] = Mathf.Clamp(lp * env * 0.9f, -1f, 1f);
            }
            var clip = AudioClip.Create($"ProcZombie_{fStart}", len, 1, sr, false);
            clip.SetData(data, 0);
            return clip;
        }

        private static AudioClip CreateEngineLoopClip(float f1, float f2, float raspAmt, float pulseHz)
        {
            const int sr = 44100;
            float dur = 1f; // periodo exato de 1s para loop sem estalo!
            int len = sr;
            var data = new float[len];
            var rng = new System.Random((int)(f1 * 17));
            float lp = 0f;
            for (int i = 0; i < len; i++)
            {
                float t = i / (float)sr;
                float s1 = Mathf.Sin(2f * Mathf.PI * Mathf.Round(f1) * t);
                float s2 = Mathf.Sin(2f * Mathf.PI * Mathf.Round(f2) * t) * 0.45f;
                float s3 = Mathf.Sin(2f * Mathf.PI * Mathf.Round(f1 * 3f) * t) * 0.20f;
                float pulse = 0.78f + 0.22f * Mathf.Sin(2f * Mathf.PI * Mathf.Round(pulseHz) * t);
                float n = (float)(rng.NextDouble() * 2.0 - 1.0);
                lp = Mathf.Lerp(lp, n, 0.08f);
                data[i] = Mathf.Clamp(((s1 + s2 + s3) * 0.42f + lp * raspAmt) * pulse, -1f, 1f);
            }
            var clip = AudioClip.Create($"ProcEngine_{f1}", len, 1, sr, false);
            clip.SetData(data, 0);
            return clip;
        }

        private static AudioClip CreateNoiseLoopClip(float vol)
        {
            const int sr = 44100;
            int len = sr;
            var data = new float[len];
            var rng = new System.Random(42);
            float lp = 0f, prev = 0f;
            for (int i = 0; i < len; i++)
            {
                float n = (float)(rng.NextDouble() * 2.0 - 1.0);
                lp = Mathf.Lerp(lp, n, 0.22f);
                float hp = lp - prev * 0.85f;
                prev = lp;
                data[i] = Mathf.Clamp(hp * vol, -1f, 1f);
            }
            var clip = AudioClip.Create("ProcDriftLoop", len, 1, sr, false);
            clip.SetData(data, 0);
            return clip;
        }
    }
}
