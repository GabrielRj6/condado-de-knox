using System.Collections.Generic;
using FishNet.Object;
using FishNet.Object.Synchronizing;
using KnoxSurvival.Audio;
using KnoxSurvival.Player;
using UnityEngine;
using UnityEngine.AI;

namespace KnoxSurvival.Zombies
{
    /// <summary>
    /// IA Autoritativa de Zumbi rodando no Servidor (FishNet v4) para que TODOS os jogadores
    /// vejam exatamente os mesmos zumbis, com audio 3D de gemido, alerta, ataque, dor e morte.
    /// </summary>
    public class ZombieAI : NetworkBehaviour
    {
        public static readonly List<ZombieAI> AllZombies = new();

        [Header("Atributos")]
        public float maxHealth = 100f;
        public float walkSpeed = 1.65f;
        public float chaseSpeed = 4.6f;
        public float detectRange = 22f;
        public float attackRange = 1.65f;
        public int attackDamage = 16;
        public float attackCooldown = 1.2f;

        public readonly SyncVar<float> Health = new SyncVar<float>(100f);
        public readonly SyncVar<bool> IsDead = new SyncVar<bool>(false);
        public readonly SyncVar<bool> IsChasing = new SyncVar<bool>(false);
        public readonly SyncVar<float> VocalPitch = new SyncVar<float>(1.0f);

        private NavMeshAgent _agent;
        private float _alertTimer;
        private float _attackCd;
        private float _wanderTimer;
        private Vector3 _wanderDir;
        private float _localVocalCd;
        private bool _wasChasingLocal;

        private void Awake()
        {
            _agent = GetComponent<NavMeshAgent>();
        }

        private void OnEnable()
        {
            if (!AllZombies.Contains(this)) AllZombies.Add(this);
        }

        private void OnDisable()
        {
            AllZombies.Remove(this);
        }

        public override void OnStartServer()
        {
            base.OnStartServer();
            Health.Value = maxHealth;
            VocalPitch.Value = Random.Range(0.84f, 1.18f);
            _wanderDir = Quaternion.Euler(0f, Random.Range(0f, 360f), 0f) * Vector3.forward;
        }

        public override void OnStartClient()
        {
            base.OnStartClient();
            _localVocalCd = Random.Range(1.5f, 6.5f);
            IsDead.OnChange += (_, dead, _) =>
            {
                if (dead)
                {
                    // Deita o corpo do zumbi ao morrer
                    transform.Rotate(82f, 0f, 0f, Space.Self);
                    if (_agent != null) _agent.enabled = false;
                }
            };
        }

        private void Update()
        {
            if (IsDead.Value) return;

            if (base.IsServerInitialized)
            {
                TickServerAI(Time.deltaTime);
            }

            if (base.IsClientInitialized)
            {
                TickClientSpatialVocals(Time.deltaTime);
            }
        }

        private void TickServerAI(float dt)
        {
            _attackCd = Mathf.Max(0f, _attackCd - dt);
            _alertTimer = Mathf.Max(0f, _alertTimer - dt);

            SurvivorController nearest = null;
            float nearestDist = float.MaxValue;
            foreach (var s in SurvivorController.AllSurvivors)
            {
                if (s == null || s.IsDead.Value) continue;
                float d = Vector3.Distance(transform.position, s.transform.position);
                if (d < nearestDist)
                {
                    nearestDist = d;
                    nearest = s;
                }
            }

            if (nearest != null && nearestDist <= detectRange)
            {
                _alertTimer = Mathf.Max(_alertTimer, 10f);
            }

            bool chasing = _alertTimer > 0f && nearest != null;
            IsChasing.Value = chasing;

            if (chasing)
            {
                if (nearestDist <= attackRange && nearest.CurrentVehicle == null)
                {
                    if (_attackCd <= 0f)
                    {
                        _attackCd = attackCooldown;
                        nearest.ApplyServerDamage(attackDamage);
                        RpcPlayZombieVocal((int)ZombieVocalType.Attack);
                    }
                    StopMoving();
                }
                else
                {
                    MoveTowards(nearest.transform.position, chaseSpeed, dt);
                }
            }
            else
            {
                _wanderTimer -= dt;
                if (_wanderTimer <= 0f)
                {
                    _wanderTimer = Random.Range(3f, 6.5f);
                    _wanderDir = Quaternion.Euler(0f, Random.Range(0f, 360f), 0f) * Vector3.forward;
                }
                MoveTowards(transform.position + _wanderDir * 4f, walkSpeed, dt);
            }
        }

        private void MoveTowards(Vector3 target, float speed, float dt)
        {
            if (_agent != null && _agent.enabled && _agent.isOnNavMesh)
            {
                _agent.speed = speed;
                _agent.SetDestination(target);
                return;
            }

            // Fallback suave sem NavMesh (funciona imediatamente mesmo antes de dar Bake no NavMesh!)
            Vector3 flat = target - transform.position;
            flat.y = 0f;
            if (flat.sqrMagnitude > 0.04f)
            {
                Vector3 dir = flat.normalized;
                transform.rotation = Quaternion.Slerp(transform.rotation, Quaternion.LookRotation(dir), dt * 6f);
                transform.position += dir * (speed * dt);
            }
        }

        private void StopMoving()
        {
            if (_agent != null && _agent.enabled && _agent.isOnNavMesh)
            {
                _agent.ResetPath();
            }
        }

        private void TickClientSpatialVocals(float dt)
        {
            if (SpatialAudio3D.Instance == null || Camera.main == null) return;
            float dist = Vector3.Distance(Camera.main.transform.position, transform.position);
            if (dist > 52f) return;

            bool chasing = IsChasing.Value;
            _localVocalCd = Mathf.Max(0f, _localVocalCd - dt);

            if (chasing && !_wasChasingLocal)
            {
                _wasChasingLocal = true;
                SpatialAudio3D.Instance.PlayZombieVocal3D(ZombieVocalType.Alert, transform.position, VocalPitch.Value);
                _localVocalCd = Random.Range(3f, 5.5f);
            }
            else if (!chasing && _wasChasingLocal)
            {
                _wasChasingLocal = false;
            }
            else if (_localVocalCd <= 0f)
            {
                if (chasing && dist < 38f)
                {
                    SpatialAudio3D.Instance.PlayZombieVocal3D(ZombieVocalType.Chase, transform.position, VocalPitch.Value);
                    _localVocalCd = Random.Range(3.2f, 6.2f);
                }
                else if (!chasing && dist < 32f)
                {
                    SpatialAudio3D.Instance.PlayZombieVocal3D(ZombieVocalType.Idle, transform.position, VocalPitch.Value);
                    _localVocalCd = Random.Range(5.5f, 11.5f);
                }
                else
                {
                    _localVocalCd = 2.5f;
                }
            }
        }

        public void AlertBySound(float duration = 14f)
        {
            if (!base.IsServerInitialized || IsDead.Value) return;
            _alertTimer = Mathf.Max(_alertTimer, duration);
        }

        public void ApplyServerDamage(float dmg, Vector3 knockDir)
        {
            if (!base.IsServerInitialized || IsDead.Value) return;
            Health.Value = Mathf.Max(0f, Health.Value - dmg);
            _alertTimer = 18f;

            if (Health.Value <= 0f)
            {
                IsDead.Value = true;
                RpcPlayZombieVocal((int)ZombieVocalType.Death);
                Destroy(gameObject, 25f);
            }
            else
            {
                RpcPlayZombieVocal((int)ZombieVocalType.Hurt);
            }
        }

        [ObserversRpc]
        private void RpcPlayZombieVocal(int vocalTypeIdx)
        {
            if (SpatialAudio3D.Instance != null)
            {
                SpatialAudio3D.Instance.PlayZombieVocal3D((ZombieVocalType)vocalTypeIdx, transform.position, VocalPitch.Value);
            }
        }

        public static void AlertZombiesInRadius(Vector3 origin, float radius)
        {
            float r2 = radius * radius;
            for (int i = 0; i < AllZombies.Count; i++)
            {
                var z = AllZombies[i];
                if (z != null && !z.IsDead.Value && (z.transform.position - origin).sqrMagnitude <= r2)
                {
                    z.AlertBySound(14f);
                }
            }
        }
    }
}
