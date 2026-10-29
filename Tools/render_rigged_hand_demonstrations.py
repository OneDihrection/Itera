# render_rigged_hand_demonstrations.py
# Created by Amelia Putri Aftiana on 29/10/2026.
# Render the adapted user-provided rig as videos and transparent catalog thumbnails.
import bpy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
scene = bpy.data.scenes['IteraRiggedHand']
bpy.context.window.scene = scene
if hasattr(scene,'eevee') and hasattr(scene.eevee,'taa_render_samples'):
    scene.eevee.taa_render_samples = 32
folder = ROOT / 'Itera/Resources/Animations/Fingers'
folder.mkdir(parents=True,exist_ok=True)
scene.render.image_settings.media_type = 'VIDEO'
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format = 'QUICKTIME'
scene.render.ffmpeg.codec = 'H264'
scene.render.ffmpeg.constant_rate_factor = 'MEDIUM'
scene.render.film_transparent = False
for name,start,end in [
    ('fullFist',1,96),('hookFist',97,192),('opposition',193,576),
    ('spreading',577,672),('extensionSequence',673,1056),
]:
    scene.frame_start = start
    scene.frame_end = end
    scene.render.filepath = str(folder / (name+'.mov'))
    bpy.ops.render.render(animation=True,scene=scene.name)
    print('EXPORTED',name,flush=True)

scene.render.image_settings.media_type = 'IMAGE'
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
for name,frame in [('hand-hero',1),('hand-fullFist',48),('hand-hookFist',144),('hand-opposition',240),('hand-spreading',624),('hand-extensionSequence',720)]:
    asset = ROOT / 'Itera/Assets.xcassets' / (name+'.imageset')
    asset.mkdir(parents=True,exist_ok=True)
    scene.frame_set(frame)
    scene.render.filepath = str(asset / (name+'.png'))
    bpy.ops.render.render(write_still=True,scene=scene.name)
    (asset/'Contents.json').write_text(json.dumps({'images':[{'filename':name+'.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
    print('THUMBNAIL',name,flush=True)
