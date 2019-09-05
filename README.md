# piring
Controlling a school bell system from the Pi

## Usage
`ring`

Reads files `ringdates`, `ringtimes` and `ringtones` from the same directory
as where the `ring` script resides. These are checked for proper syntax & semantics, and when OK the program starts and keeps running, logging output to stdout.
### Format
- ringdates: 'YYYY-MM-DD' (No School dates) or 'YYYY-MM-DD s' where 's' is
  the alphabetical special Schedule code (capital cancels Normal schedule)
- ringtimes: 'HH:MMsr' where 's' is the corresponding Special schedule code
  (or space for the Normal schedule) and 'r' is the Ringtone code (which
  refers to a line in the 'ringtones' file that specifies a .wav file).
  The 'r' can be left out for the Normal '0' code.
- ringtones: 'filename' where 'filename' is the location of a .wav file
  The first line is code '0', the Normal ring tone, the rest is '1' and
  upwards (maximum is '9'), the last line is the Alarm tone.

### Workings

Every weekday the Normal schedule will ring and additional schedules with a
lowercase schedule code, but on special dates with an uppercase schedule the
Normal schedule will not ring.

## Required
wiringpi(gpio) coreutils(sleep fold readlink) alsa-utils(aplay) date [tmux]

## Deployment
To have it autostart on reboot, the script `ringatreboot` can be called from cron at reboot (see `ringcrontab` for an example). This uses tmux, so the session can be attached to when logging in. Alternatively, `ring` can just be called and the output directed to a file.

## Licence
GPLv3+
