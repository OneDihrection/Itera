# render_rigged_hand_demonstrations.py
# Created by Amelia Putri Aftiana on 29/10/2026.
# Render the adapted user-provided rig as MP4 clips and transparent catalog thumbnails.
import bpy
import json
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
scene = bpy.data.scenes['IteraRiggedHand']
bpy.context.window.scene = scene
if hasattr(scene,'eevee') and hasattr(scene.eevee,'taa_render_samples'):
    scene.eevee.taa_render_samples = 32
folder = ROOT / 'Tuntun/Resources/Animations'
folder.mkdir(parents=True,exist_ok=True)
# Clips follow Documentation/AnimationRenderingStandard.md: 768 x 768, 24 FPS, transparent PNG
# frames composited over #F5F5F5 and encoded as silent H.264 yuv420p (CRF 18) with FFmpeg.
scene.render.resolution_x = 768
scene.render.resolution_y = 768
scene.render.resolution_percentage = 100
scene.render.fps = 24
scene.render.image_settings.media_type = 'IMAGE'
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
for name,start,end in [
    ('full_fist',1,96),('hook_fist',97,192),('opposition',193,576),
    ('spreading',577,672),('extension_sequence',673,1056),
]:
    frames = Path(tempfile.mkdtemp(prefix=name+'_'))
    scene.frame_start = start
    scene.frame_end = end
    scene.render.filepath = str(frames / 'frame_')
    bpy.ops.render.render(animation=True,scene=scene.name)
    subprocess.run([
        'ffmpeg','-y','-f','lavfi','-i','color=c=#F5F5F5:s=768x768:r=24',
        '-framerate','24','-start_number',str(start),'-i',str(frames / 'frame_%04d.png'),
        '-filter_complex','[0][1]overlay=shortest=1,format=yuv420p',
        '-c:v','libx264','-crf','18','-an','-movflags','+faststart',
        str(folder / (name+'_demonstration.mp4')),
    ],check=True)
    shutil.rmtree(frames)
    print('EXPORTED',name,flush=True)

scene.render.image_settings.media_type = 'IMAGE'
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.film_transparent = True
for name,frame in [('hand-hero',1),('hand-fullFist',48),('hand-hookFist',144),('hand-opposition',240),('hand-spreading',624),('hand-extensionSequence',720)]:
    asset = ROOT / 'Tuntun/Assets.xcassets' / (name+'.imageset')
    asset.mkdir(parents=True,exist_ok=True)
    scene.frame_set(frame)
    scene.render.filepath = str(asset / (name+'.png'))
    bpy.ops.render.render(write_still=True,scene=scene.name)
    (asset/'Contents.json').write_text(json.dumps({'images':[{'filename':name+'.png','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
    print('THUMBNAIL',name,flush=True)
