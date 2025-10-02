# ShowInAppleMusic

## What it does

In Apple Music, provides a mouse binding to open the current item in "Apple Music," meaning, show streaming options.

## Why it exists

Apple, in their infinite wisdom, decided that streaming music in the Apple Music is a second-class citizen. Unlike in any other streaming app, if I want to listen to an album by an artist, I first have to right-click on that artist, then click on "Show in Apple Music," and then proceed to choose the album.

It's terrible UX.

So I vibe coded this workaround.

## Usage

This assumes you have Hammerspoon installed.

1. Clone this repo to `~/.hammerspoon/Spoons/ShowInAppleMusic.spoon`
2. In your `~/.hammerspoon/init.lua`, add the following:

```lua
hs.loadSpoon("ShowInAppleMusic")
hs.spoons.ShowInAppleMusic:openDelay = 0.10 -- tweak if necessary, defaults to 0.10
hs.spoons.ShowInAppleMusic:clickModifiers = { alt = true } -- optional, defaults to { alt = true }
```

3. Reload your config.

Now when you are in Apple Music, you can hold `Option` and click on an item to show the streaming options.
