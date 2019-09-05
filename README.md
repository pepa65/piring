# piring
Controlling a school bell system from the Pi

## Usage
`ring`

Reads files `ringdates`, `ringtimes` and `ringtones` from the same directory
as where the `ring` script resides. These are checked for proper syntax &
semantics, and when OK the program starts and keeps running, logging output to
stdout.

### Format
- **ringdates**: lines with `YYYY-MM-DD` (No School dates) or `YYYY-MM-DD s`,
  where `s` is the alphabetical special Schedule code (uppercase cancels the
  Normal schedule, lowercase is in addition to the Normal schedule).
- **ringtimes**: lines with `HH:MM` (Normal schedule), `HH:MMs` (Special
schedule) or `HH:MMsr`, where `s` is the corresponding Special schedule code
  (or space for the Normal schedule) and `r` is the Ringtone code (which
  refers to a line in the `ringtones` file that specifies a *.wav* file).
  When `r` is the default `0` code, it can be left out.
- **ringtones**: lines with `filename`, where `filename` is the filesystem
  location of a *.wav* file. The file in the first line is referred to by
  code `0` (the Normal ring tone), the next lines are `1` and up (the maximum
  is `9`), the last line is the special Alarm tone.

### Workings

Every weekday the Normal schedule will ring and additional schedules with a
lowercase schedule code. On Special dates with an uppercase Schedule code the
Normal schedule will not ring.

## Required
wiringpi(gpio) coreutils(sleep fold readlink) alsa-utils(aplay) date [tmux]

## Deployment
To have it autostart on reboot, the script `ringatreboot` can be called from cron at reboot (see `ringcrontab` for an example which uses **tmux**, so the session can be attached to when logging in). Alternatively, `ring` can just be called and the output directed to a file, like: `ring >ring.log`

## Licence
GPLv3+
