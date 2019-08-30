# piring
Controlling a school bell system from the Pi

## Usage
`ring`

Two files, ringdates (for exeptions) and ringtimes (for the schedules) are read.These are checked for proper syntax & semantics, and when OK the program starts
and keeps running, logging output to stdout.

### Format
* Ringdates: `YYYY-MM-DD d` where `d` is the Day type:
  - `X`: No School
  - `L`: Late Start
* Ringtimes: `HH:MM s` where `s` is the ring Schedule:
  - `N`: Normal
  - `E`: Elementary Normal
  - `L`: Late Start
  - `e`: Elementary Late Start

## Required
wiringpi(gpio) coreutils(sleep fold) alsa-utils(aplay) date [tmux/screen]

## Deployment
To have it autostart on reboot, the script `ringatreboot` can be called from cron at reboot (see `ringcrontab` for an example). This uses tmux, so the session can be attached to when logging in. Alternatively, `ring` can just be called and the output directed to a file.

## Licence
GPLv3+
