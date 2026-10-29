# render_finger_demonstrations.py
# Created by Amelia Putri Aftiana on 29/10/2026.
# Run with Blender --background ArtSource/FingerDemonstrations.blend --python this_file.
import bpy
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
scene = bpy.data.scenes['IteraFingerDemonstrations']
bpy.context.window.scene = scene
scene.render.image_settings.media_type = 'VIDEO'
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format = 'QUICKTIME'
scene.render.ffmpeg.codec = 'H264'
scene.render.ffmpeg.constant_rate_factor = 'MEDIUM'
folder = ROOT / 'Itera/Resources/Animations/Fingers'
folder.mkdir(parents=True, exist_ok=True)
if hasattr(scene, 'eevee') and hasattr(scene.eevee, 'taa_render_samples'):
    scene.eevee.taa_render_samples = 24
for name, start, end in [
    ('fullFist', 1, 48), ('hookFist', 49, 96), ('opposition', 97, 288),
    ('spreading', 289, 336), ('extensionSequence', 337, 528),
]:
    scene.frame_start = start
    scene.frame_end = end
    scene.render.filepath = str(folder / (name + '.mov'))
    bpy.ops.render.render(animation=True, scene=scene.name)
    print('EXPORTED', name, flush=True)
