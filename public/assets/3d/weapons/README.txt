FORJA 3D — ARSENAL LOW-POLY COMPLETO
====================================

Acabamento: Tático Padrão (Desgaste: 35%)
Nível LOD:  Game-Ready (FPS Padrão)
Total:      15 armas (7.520 triângulos no pacote inteiro)

ESTRUTURA DE PASTAS POR CATEGORIA E ARMA
----------------------------------------
01_fuzis/          -> M41-T, AK-74M, SR-76
02_pistolas/       -> P9-K, MAG-44
03_cqb/            -> SG-12, DB-68, VX-9
04_pesadas/        -> MG-240, RL-84, M67-G
05_scifi_e_melee/  -> PL-09, CB-X, K-BAR, KAT-0

CONTEÚDO DENTRO DA PASTA DE CADA ARMA
-------------------------------------
- *.glb            : Modelo 3D Low-Poly pronto com texturas PBR embutidas e nós 3D socket_*
- *.obj            : Malha Low-Poly limpa em OBJ
- *_hud_icon.png   : Ícone lateral com fundo transparente para inventário/HUD
- spec.json        : Especificação completa (RPM, modos de fogo, carregador, recarga, topologia)
- sockets.json     : Coordenadas 3D de muzzle, grip, ejection, optic e trilhos
- textures/        : Mapas PBR individuais em PNG (albedo, normal, roughness, metalness)

DICA DE IMPORTAÇÃO (Unity / Unreal / Godot / Three.js)
------------------------------------------------------
- Os arquivos .GLB já incluem as texturas PBR embutidas e os nós vazios:
  socket_muzzle, socket_grip, socket_ejection e socket_optic.
- Sistema de coordenadas: mão direita (+Y cima, +X frente/cano, +Z direita).
- Use manifest.json na raiz para carregar o catálogo inteiro automaticamente.
