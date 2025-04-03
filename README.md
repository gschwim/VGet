Binary download in the dist folder!

# VGet - Video Get

I whipped this app up for my wife after about a year of her asking me to rip
content down from the various alleyways and basements of the 7 levels of the
social media hellscape.

Any by "I whipped this app up," I mean I asked the venerable Grokster do 
do the heavy lifting for me. All I had to do was poke it and prod it just so
until it gave me what I asked for. Grok is pretty smart, and this here bit of
hackery is a direct outcome of asking it to do it for me twice.

The first prompt I used was as follows:

```quote
using python, the kivy UI framework, and the python tool yt-dlp, create a small program that will:

 - take a URL of a video as input
 - use yt-dlp to download it, using the --cookies-from-browser switch, using the browser chrome as input
 - download the video from the url provided into the ~/Downloads folder

This should all be done in a single .py file with no external .kv needed.
```

Being a passivly inattentive child, I had to ask it a second time if only to
remind it that I wanted what I asked for. I'll leave it to you to decide what
I asked.

### A note for the casual kivy / yt-dlp / pyinstaller adventurist

yt-dlp really likes its stderr to be, er, well, stderr. So much so that when
its not quite what it is expecting, it complains vaguely. Interestingly, this
isn't really noticed, most of the time, when running this program from the cli.
Nope - you need to build it with pyinstaller and run the package for it to let
you know.

As you may notice, if you've bothered to read this ridiculous bit of code here,
there is *no* logging output. Why expend the effort? Grok wrote this, and 
without doubt it should _just work_. 

Anyway, I eventually realized I needed to force kivy to let yt-dlp have its
plain old stderr back. From there, we go.

Any bugs you might find beyond this are courtesy of the illustrious Mr. Musk
and his cohort of merry Groks!

- gs
