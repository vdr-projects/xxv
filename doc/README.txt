Electronically translated, still another correction of the grammar and orthography needs
----------------------------------------------------------------------------------------
Hello friends,

now has I mean menace was made and a first Framework for XXV (Xtreme eXtension for Vdr) 
made true. Naturally need I unite testers this project there is rather extensive. 
Over perhaps it would be beautiful even if those little Perl can me with the Plugins help.

To you are simply by Mail to me if you announce interested !

But for the time being... some explanations which actually XXV is;)

As know some from you, I worked in former times much to vdradmin. 
By this work came at the end as vdradmin "BigPatch" ... 
finally it however only one sprag was to be extended by the existing vdradmin.

With this work on the Patch me a simpler solution floated before substantially 
structure and more simply to always extend is. It is to be able to serve a 
central service to exist with that different of haven is open and these 
different services. An additional haven over a Plugin to furnish, 
should be just as simple, as placing also a certain service ready. 
Write a Plugins goes very fast there the input (Vdr, railways etc.) 
as well as the output (telnet, HTTP...) generically was realized.

It should be e.g. possible thus to register with a telnet CONSOLE, HttpBrowser, 
WapPhone, etc. pp. an autotimer. This should be able to scan substantially 
faster the EPG data (MySQL data base) and over an interface vdr the new timer
 communicates. Naturally also is considered to the single mode of the SVdrP 
and only one instruction is mailed and again the haven is closed immediately, 
so that other programs can access again svdrp. 

Long speech short sense, here a small overview of the present functions:

    * completely in Perl realizes
    * very generic front-end
    * Plugin system
    * Data base support
    * Epg data are regularly parsed and registered
    * very simple Plugin concept for future extensions
    * several services from a service (Telnet, HTTP, ...)
    * Dump interface for external programs 

That was realized everything the Event module and naturally a MySQL data base, 
which takes up all data (timer, epg, channels) and thereby also marvelously 
the things to be reorganized to be able..

A guidance for installing and description in more detail find it under:

http://www.linuxtv.org/vdrwiki/index.php/Xxv

Legal stuff
-----------

   (c) Copyright 2004-2005  Frank Herrmann / Berlin.
   All rights reserved.

   Written by Frank Herrmann <xpix at xpix dot de> and
              Andreas Brachold <vdr04 at deltab dot de>.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   The complete text of the license is found in the file COPYING.
