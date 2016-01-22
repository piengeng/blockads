# blockads.pl
This is a perl script I'd created for personal usage to block annoying ads and malicious sites, use at your own risk.

## Requirements:
* Linux/Windows with perl and bind9 installed. Refer [lin](https://wiki.debian.org/Bind9) or [win](http://www.zytrax.com/books/dns/ch5/win2k.html) to learn how-to.
* Know how to read/modify perl scripts in case installation differences.
* optional crontab edits if you want to run this script periodically.

### Assume:
bind9 installed to `/etc/bind` or `C:\Program Files\ISC BIND 9` , or else modifications to the script is needed.

modify `named.conf` if you know how/like.

windows note: copy blockads/config/only4win/* to `C:\Program Files\ISC BIND 9\etc` is needed. Not needed for linux.

### Run the script with privileged access:
`perl ./blockads.pl` in linux, or `perl blockads.pl` in windows.

`/etc/init.d/bind9 restart` or `WIN+R > services.msc`, find "ISC BIND" and restart.

#### Enjoy ad-free paid internet!