KNOX SURVIVAL 3D (GODOT 4) — PASTA PLUG-AND-PLAY DE ASSETS

Voce pode soltar arquivos 3D, animacoes e sons da Godot Asset Store ou Mixamo nestas pastas que o jogo detecta automaticamente:

1. Modelos 3D de Personagem / Zumbi:
   res://assets/characters/
   - player.glb (ou swat.glb / survivor.glb) -> substitui o boneco do jogador automaticamente e acopla a arma 3D na mao direita (RightHand)!
   - zombie.glb -> substitui o modelo dos zumbis!

2. Animacoes externas (.glb, .gltf, .tres, .res):
   res://assets/animations/
   - Coloque aqui seus clips (ex: rifle_idle.glb, walk_fwd.glb, run_fwd.glb, strafe_left.glb, strafe_right.glb, crouch.glb, reload.glb).
   - O AssetBridge.gd junta automaticamente todas essas animacoes no AnimationPlayer do personagem!

3. Sons reais (.wav, .ogg, .mp3):
   res://assets/audio/
   - Nomes reconhecidos automaticamente: gun_rifle, gun_pistol, gun_sniper, gun_suppressed, engine_car, engine_moto, engine_street, zombie_idle, zombie_alert, zombie_attack, zombie_death.

4. Plugins da Godot Asset Store (Sky3D, Terrain3D, TerraBrush, RoadGenerator):
   res://addons/
   - Ative o plugin em Project -> Project Settings -> Plugins.
   - Se voce adicionar um no Sky3D, Terrain3D ou TerraBrush na cena Main.tscn, o MainWorld.gd respeita automaticamente sem sobrescrever!
