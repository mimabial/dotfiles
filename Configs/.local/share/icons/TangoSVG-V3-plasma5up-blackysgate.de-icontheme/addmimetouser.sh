#!/bin/bash

# version from 2024-12-31 10:08

#
# Blackysgate extra Mimetypes for Linux + Extra Icons
# this script installs the important mimetypes for automatical mapped the right icons to the files,
# like in etc as example hosts file or locale.conf or fstab and mtab, my iconthemes supports
# these with the right icons and let see you not easy gray icons, now you can learn about and
# have the right Icons mapped on the right files.
# Something is the wrong MS hate and for more savety hide the right Icon files for more "security n savety"...
# bleargh.... therefor have i make in my icontheme the right Icons and give therewith the
# possible for map the files to the right Icons with the Mimetypes-Database and then can the WM like Plasma and others
# can display the icons for them. For more better understand in right way and learning in right way with the right Icons,
# also for a better file handling by working with the right Icons for a better right understand even in retrospect.
# So manny fun !
# Adding a Mimetype is noting bad and breaks not the security, it's makes possibility for display the right icons.
#
# So check the script make "chmod 550 thisscript.sh and let it run via ./thisscript.sh , Manny pfffuuuhhnnn :)
#
# these Files be then ico'ed with this script :
# fstab, mtab/mounts , exports , system-release, hostname, hosts,locale.conf,
#    *.ini ,*.conf, *.cfg, *.blacklist, *.dll; *.ocx ,*.cpl,
#      *.sys, *.vbs; *.cmd ; *.bat , *.com, *.dll, *.msi
#  and other Icons where not included the Mimetype-listing of the System
#
# And be only right Displayed if these Icons in the System or in your installed Icontheme
# and the right Icontheme exist. check out in the Script what for 'icon names=' these be
#
# i don't understand up to now, why the Linux important files still not be icon'ed/Mimetyped !!
# this is important for learn about the own linus system and give the hint for
# importantness these files in the system !
#
# best regards
# Blacky

# https://unix.stackexchange.com/questions/564816/how-to-install-a-new-custom-mime-type-on-my-linux-system-using-cli-tools

# - Mode can be "user" as normal User or "system", but then as Admin/root with sudo
instmode="--mode user --novendor"

clear
printf " \n \n
 Blackys Mimetype Icons type register Bash script
 ================================================
 this script register now the Icons to the Mimetypes
 in your Linuxsystem via 'xdg-mime' Programm,
 it's copy the text into a xml-text-file and this file
 is used with 'xdg-mime' cmd programm to add the info
 into the Mimedatabase, this script is conured as user mode
 for use in the own useraccount and don't change the whole
 System, only in the Useraccount !
 Manny fun with the whole extra Icons !
 Blacky
 Blackysgate
 \n\n"


#check if a folder exist , with -f it's meant a file and with -d a directory/folder
if [ -d "$HOME/.local/share/mime" ] ; then
 echo ""
 echo "/$HOME/.local/share/mime already exist"
 echo ""
 else
 mkdir $HOME/.local/share/mime
 echo "/$HOME/.local/share/mime now created"
 echo ""
fi
sleep 3

rm -f $HOME/.local/share/mime/packages/blackys-extra*


echo " Register Mime File .directory "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type  type="text/x-directory">
  <comment>Folder definitions-File</comment>
  <icon name="text-x-directory"/>
  <glob pattern=".directory"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-desktop.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-desktop.xml

echo " Register Mime File .sfv checksum "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type  type="text/x-checksum">
  <comment>Checksum file uses CRC32, MD5, SHA-256 and others </comment>
  <icon name="text-x-checksum"/>
  <glob pattern="*.sfv"/>
  <glob pattern="*.sha"/>
  <glob pattern="*.md5"/>
  <glob pattern="*.crc"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-checksum.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-checksum.xml

echo " Register Mime File .windows-serial from Wine"
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type  type="text/x-winedrive">
  <comment>Wine Drive Serial Number definition</comment>
  <icon name="text-x-winedrive"/>
  <glob pattern=".windows-serial"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-wine-serial.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-wine-serial.xml

echo " Register Mime File fstab "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type  type="text/x-fstab">
  <comment>info-File for mounted fs linked in /etc readed out from /prog/self/mounts</comment>
  <icon name="text-x-fstab"/>
  <glob pattern="fstab"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-fstab.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-fstab.xml

echo " Register Mime File mtab "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type  type="text/x-mtab">
  <comment>info-File for mounted fs linked in /etc readed out from /prog/self/mounts</comment>
  <icon name="text-x-mtab"/>
  <glob pattern="mtab"/>
  <glob pattern="mounts"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-mtab.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-mtab.xml

echo " Register Mime File exports "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type  type="text/x-exports">
  <comment>Conf-File for NFS Server /etc</comment>
  <icon name="text-x-exports"/>
  <glob pattern="exports"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-exports.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-exports.xml

echo " Register Mime File .ini -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type  type="text/x-ini">
  <comment>Conf-Files from this computer, most in /etc</comment>
  <icon name="text-x-ini"/>
  <glob pattern="*.ini"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-ini.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-ini.xml

echo " Register Mime File .conf -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type  type="text/x-conf">
  <comment>Conf-Files from this computer, most in /etc</comment>
  <icon name="text-x-conf"/>
  <glob pattern="*.conf"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-conf.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-conf.xml

echo " Register Mime File .cfg -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="text/x-cfg">
  <comment>Conf-Files from this computer, most in /etc</comment>
  <icon name="text-x-cfg"/>
   <glob pattern="*.cfg"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-cfg.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-cfg.xml

echo " Register Mime File blacklist -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="text/x-blacklist.conf">
  <comment>A Blacklist File of the Modules, Ip s and so on</comment>
  <icon name="text-x-blacklist"/>
  <glob pattern="blacklist.conf"/>
  <glob pattern="*.blacklist"/>
  <glob pattern="blacklist"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-blacklistconf.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-blacklistconf.xml

echo " Register Mime File system-release "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="text/x-system-release">
  <comment>The Ordering System Release of your Computer</comment>
  <icon name="text-x-system-release"/>
   <glob pattern="system-release"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-system-release.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-system-release.xml

echo " Register Mime File hostname "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="text/x-hostname">
  <comment>Hostname file of your Computer</comment>
  <icon name="text-x-hostname"/>
   <glob pattern="hostname"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-hostname.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-hostname.xml

echo " Register Mime File hosts "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="text/x-hosts">
  <comment>Hosts info File local known Net Computers IP n Name.dom n Name</comment>
  <icon name="text-x-hosts"/>
   <glob pattern="hosts"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-hosts.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-hosts.xml

echo " Register Mime File locale.conf "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="text/x-locale">
  <comment>a Locale System configuration File</comment>
  <icon name="text-x-locale"/>
   <glob pattern="locale.conf"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-locale.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-locale.xml


echo " Register Mime File .dll - files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-dll">
  <comment>Wine n Reactos Library File</comment>
  <icon name="application-x-dll"/>
   <glob pattern="*.dll"/>
  </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-dll.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-dll.xml

echo " Register Mime File .ocx -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-ocx">
  <comment>Wine, Reactos  Library File</comment>
  <icon name="application-x-ocx"/>
   <glob pattern="*.ocx"/>
   </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-ocx.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-ocx.xml

echo " Register Mime File .cpl -Files"
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-cpl">
  <comment>Wine, Reactos Configuration Control Panel File</comment>
  <icon name="application-x-cpl"/>
   <glob pattern="*.cpl"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-cpl.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-cpl.xml

echo " Register Mime File .sys -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-sys">
  <comment>Wine, Reactos System File</comment>
  <icon name="application-x-sys"/>
   <glob pattern="*.sys"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-sys.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-sys.xml

echo " Register Mime File .VBS -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-vbs">
  <comment>Computer Language Visual Basic File</comment>
  <icon name="application-x-vbs"/>
   <glob pattern="*.vbs"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-vbs.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-vbs.xml

echo " Register Mime File .nls -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-nls">
  <comment>Wine, Reactos System File</comment>
  <icon name="application-x-nls"/>
   <glob pattern="*.nls"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-nls.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-nls.xml

echo " Register Mime File .mui -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-mui">
  <comment>Wine, Reactos MUI File</comment>
  <icon name="application-x-nls"/>
   <glob pattern="*.mui"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-mui.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-mui.xml

echo " Register Mime File .cmd -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-cmd">
  <comment>Dos, Wine, Reactos Command Line File</comment>
  <icon name="application-x-cmd"/>
   <glob pattern="*.cmd"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-cmd.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-cmd.xml

echo " Register Mime File .bat -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-bat">
  <comment>Dos, Wine, Reactos Command Line File</comment>
  <icon name="application-x-bat"/>
   <glob pattern="*.bat"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-bat.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-bat.xml

echo " Register Mime File .com -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type type="application/x-com">
  <comment>Executable DOS, Reactos, Wine or OS/2 program</comment>
  <icon name="application-x-com"/>
   <glob pattern="*.com"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-com.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-com.xml

echo " Register Mime File .exe -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
<mime-type type="application/x-exe">
  <comment>Executable DOS, Reactos, Wine or OS/2 program</comment>
  <icon name="application-x-executable"/>
   <glob pattern="*.exe"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-exe.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-exe.xml

echo " Register Mime File .manifest -Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-manifest">
  <comment>Reactos/Wine WinNT Manifest File</comment>
  <icon name="application-x-dll"/>
   <glob pattern="*.manifest"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-manifest.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-manifest.xml

echo " Register Mime File .MSI - Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-msi">
  <comment>Reactos/Wine WinNT Microsoft System Install File</comment>
  <icon name="application-x-msi"/>
   <glob pattern="*.msi"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-msi.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-msi.xml

echo " Register Mime File .apkm - Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-apkm">
  <comment>Extended Android-Packet with apk files inside -more as one-</comment>
  <icon name="application-x-apkm"/>
   <glob pattern="*.apkm"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-apkm.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-apkm.xml

echo " Register Mime File .xapk - Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-xapk">
  <comment>Extended Android-Packet with huge files and a OBB Script -hold trusted-</comment>
  <icon name="application-x-xapk"/>
   <glob pattern="*.xapk"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-xapk.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-xapk.xml

echo " Register Mime File .apks - Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-apks">
  <comment>Android-Packet with Multi Apk files inside -more as one-</comment>
  <icon name="application-x-apks"/>
   <glob pattern="*.apks"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-apks.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-apks.xml

echo " Register Mime File .wsz - Winamp Files "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="application/x-wsz">
  <comment>Winamp Skin File</comment>
  <icon name="application-x-wsz"/>
   <glob pattern="*.wsz"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-wsz.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-wsz.xml


echo " Register Mime File .tdl - Terminal Downloader File "
printf '<?xml version="1.0" encoding="utf-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
 <mime-type type="text/tdl">
  <comment>Terminal Downloader File</comment>
  <icon name="text-tdl"/>
   <glob pattern="*.tdl"/>
 </mime-type>
</mime-info>' > $HOME/.local/share/mime/blackys-extra-icons-tdl.xml
xdg-mime install $instmode $HOME/.local/share/mime/blackys-extra-icons-tdl.xml


#===========================================================================================

echo " Updating now mimetype - database "
update-mime-database $HOME/.local/share/mime

printf " \n\n Now can you use the Theme Icons and see in
  /etc
 and other places the right Icons if the icons in the actually Theme ;)
 Also the WinNT Icons like from Wine and Reactos

 now can you call 'kcmshell5 filetypes' in KDE/Plasma
 and the bat and cmd files can you let open with wineconsole

 best , your
 Blacky
 from Blackysgate
 \n"
