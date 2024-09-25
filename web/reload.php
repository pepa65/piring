<?php
echo(system('killall -q -w -9 ring'));
echo(system('killall -q -w -9 python2.7'));
chdir($_SERVER['DOCUMENT_ROOT'].'/..'); // Location of files
echo(system('~/git/piring/getcsv -d'));
exec('~/git/piring/ring >~/git/piring/web/log &');
?>
