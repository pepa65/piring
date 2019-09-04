# piring
Controlling a school bell system from the Pi

## Usage
`ring`

Two files, ringdates (for exeptions) and ringtimes (for the schedules) are read.These are checked for proper syntax & semantics, and when OK the program starts
and keeps running, logging output to stdout.

### Format
* Ringdates: `YYYY-MM-DD s` where `s` is the alphabetical special Schedule code
(leave out for No School days)
* Ringtimes: `HH:MMsr` where `s` is the corresponding special Schedule code
(space for the Normal schedule) and `r` is the Ringtone code, which points to
the array element in `ringtones` that specifies the file name (can be left out
for the Normal `0` code).

### Workings
Normally, every weekday the Normal schedule will ring, except on dates that
are listed in the `ringdates` file, which follow a special schedule that
corresponds to the letter in the `ringtimes` file.

## Required
wiringpi(gpio) coreutils(sleep fold) alsa-utils(aplay) date [tmux/screen]

## Deployment
To have it autostart on reboot, the script `ringatreboot` can be called from cron at reboot (see `ringcrontab` for an example). This uses tmux, so the session can be attached to when logging in. Alternatively, `ring` can just be called and the output directed to a file.

## Licence
GPLv3+
