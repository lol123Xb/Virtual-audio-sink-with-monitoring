# Virtual audio sink with monitoring
Linux specific virtual audio splitting for streaming and recording on OBS, and automatic remapping of new game and audio playback sources

## Requirements
If you haven't already, you should probably install `pactl` and `pavucontrol`.

I use Ubuntu so for me, to install them I use:
```
sudo apt install pactl pavucontrol
```

## How to use

### Before you start
So to start, check `create.sh` and do any changes to these 2 lines or any additions, if you want to split your audio up more into different audio tracks

**create.sh**
```bash
# line 64
create_isolated_sink "Discord" "Discord"
create_isolated_sink "Music" "Music"
# Add more if you need more tracks
```
These 2 are more than enough for me.

As for the desktop only or game only output, that was created in the earlier code in the file and anything you want being captured for your music-less/discord-less desktop output, just move any playback sources to **Desktop** output using **PulseAudio Volume Control** which was installed via `pavucontrol`, but also, you don't have to worry about doing this manually as the `remap.sh` file has a monitoring command that will do it for you automatically.

### The proper how to use
Now that we've gotten that out of the way, when you want to start using the scripts, first, make sure you set the 3 bash files to be runnable as a program using these commands:
```bash
chmod +x create.sh
chmod +x remap.sh
chmod +x remove.sh
```

Next, you want to run `./create.sh` to let it create the virtual audio devices/sinks/outputs

After that, you can either run `./remap.sh` alone or you can add `--monitor &` to it to let it automatically remap any new playback sources or audio sources to **Desktop** only output in the background.

If you use `--monitor &` and not `--monitor`, it lets you exit the terminal as the `&` sign seems to allow running terminal commands in the background, which I only learnt while making this 😂

If you made changes to the audio sinks to either create a new one or remove one/etc, then you'll have to modify these parts of the code:

**remap.sh**
```bash
# line 86
# Process existing apps first
  move_all_games_to_desktop
  move_application_to_sink "Chromium" "Music"
  move_application_to_sink "OBS" "Desktop" # I moved the OBS monitoring output
                                            to Desktop as well because I use a
                                            capture card to record console/second
                                            pc/etc and I want the audio to be recorded
                                            as well
  move_application_to_sink "WEBRTC VoiceEngine" "Discord"
  move_application_to_sink "Discord" "Discord"

...

# line 108
# Determine target sink
local target_sink="Desktop"

if [[ "$app_name" == *"Chromium"* ]]; then
  target_sink="Music"
elif [[ "$app_name" == *"WEBRTC"* ]] || [[ "$app_name" == *"Discord"* ]]; then
  target_sink="Discord"
elif [[ "$app_binary" == *"wine"* ]] || [[ "$app_binary" == *"preloader"* ]]; then
  target_sink="Desktop"
fi
```
Modifying these lines of codes can also help if you want to manually set a specific app to not be recorded by OBS, such as moving **Brave** to the **Music** output (I use **Noutube** for my music, hence why it's using **Chromium** as the target source), since the remap monitoring will just undo your manual changes if you changed any output for specific playbacks via **PulseAudio Volume Control**

If you want to remove all of the created audio sinks/outputs, just run `./remove.sh` and if you want it to stop monitoring just run `./remap.sh --stop`
