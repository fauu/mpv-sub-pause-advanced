<!-- vim: set textwidth=80 colorcolumn=80: -->
<!-- markdownlint-configure-file
{
  "line-length": { "code_blocks": false },
  "no-inline-html": false
}
-->
# mpv-sub-pause-advanced

> A versatile [mpv] media player script for pausing video playback for subtitles

*Note: This script has not been thoroughly tested yet for all of its possible
configuration combinations. Please feel encouraged to report any suspected
issues / incompatibilities / unexpected behaviours by creating a
[Github issue][issues].

[issues]: https://github.com/fauu/mpv-sub-pause-advanced/issues
[mpv]: https://mpv.io/

## Main features

* Independently configure pausing at the start/end of the primary/secondary
  subtitle track.

* Automatically unpause after a time period dependent on the subtitle
  length (either text length or time duration).

* Pause on request: press a key to request a pause at the end of the current
  subtitle.

* Avoid pausing for subtitles below a specified length threshold.

* Avoid pausing for special subtitles, such as karaoke subtitles or
  sign subtitles.

* Hide subtitles when not paused for them.

## Installation

Download the [script file] and place it in the `scripts` subdirectory of the
mpv configuration directory (see [Script location][mpv-script-location] in mpv
manual).

[mpv-script-location]: https://mpv.io/manual/stable/#script-location
[script file]: https://raw.githubusercontent.com/fauu/mpv-sub-pause-advanced/master/sub-pause-advanced.lua

## Base usage

To enable the script, provide a setup definition as a script option to mpv. Here
is an illustration of different ways to provide the setup definition `2end`, which
instructs the script to pause at the end of each secondary subtitle:

1. Directly when launching mpv:

    ```txt
    mpv file.mkv --script-opts=sub-pause-setup=2end
    ```

1. Globally in [mpv config]:

    ```txt
    script-opts=sub-pause-setup=2end
    ```

1. As a [custom profile] in [mpv config]:

    ```txt
    [my-sub-pause-profile]
    script-opts=sub-pause-setup=2end
    ```

    then enable electively when starting mpv:

    ```txt
    mpv file.mkv --profile=my-sub-pause-profile
    ```

[mpv config]: https://mpv.io/manual/stable/#configuration-files
[custom profile]: https://mpv.io/manual/stable/#profiles

**Note: By default, pausing will be skipped when the subtitle does not met
certain conditions:**

1. The subtitle’s time duration is below the default threshold.

1. The subtitle’s text length is above zero but below the default threshold.

1. Auto unpause is enabled and the subtitle’s calculated pause duration is below
   the default threshold.

The values of these defaults and the way to override them are described in the
section [Extra options](#extra-options).

## The setup definition

### Form

The setup definition is a string of characters that tells the script when to
pause and how to do it. It is made up of up to four parts separated with the
characters `##`. Those parts each define a pause point in one of four available
positions: start of primary subtitle, end of primary subtitle, start of
secondary subtitle, end of secondary subtitle.

For example, the following definition enables pause at the start of the
secondary subtitle and at the end of the primary subtitle:

```txt
2start##end
```

Furthermore, each of the parts can be modified with extra configuration
directives separated with the `!` character. For example, to extend the
above definition with the options:

1. Hide the secondary subtitle while playing, and

1. Once paused at the end of a primary subtitle, wait a bit and then
  automatically unpause

the following setup definition ought to be specified:

```txt
2start!hide##end!unpause
```

Multiple directives can be provided within a single part. For example, to make
it so that, on top of the previous configuration, the pause at the end of a
primary subtitle only happens if a specified pause request key is pressed before
the end of the subtitle is reached, the definition should read:

```txt
2start!hide##end!unpause!request
```

Finally, some directives can have extra arguments, separated with the `-`
character, that additionally modify their behaviour. For example, to prolong the
interval before the automatic unpause for the end of a primary subtitle, for
example by factor of 1.5, specify:

```txt
2start!hide##end!unpause-1.5!request
```

### All setup parameters

#### Position specifiers

`start` — start of each primary subtitle.

`end` — end of each primary subtitle.

`2start` — start of each secondary subtitle.

`2end` — end of each secondary subtitle.

#### Directives

##### – `unpause`

Automatically unpause playback after a time interval calculated on the basis
of the subtitle text length. Note that this will not work properly for
image-based subtitled — for those, the `-time` argument must be used.

<u>Arguments:</u>

`unpause-time` — calculate the unpause interval based on the subtitle’s defined
playback time instead. Necessary for image-based subtitles, although it will not
be as accurate as the default option for text subtitles.

`unpause[-time]-<number>`

Multiply the calculated unpause interval by `<number>`. Supports decimal parts,
for example `0.75`.

Advanced modifications to the calculation formula can be made through [Extra
options](#extra-options).

##### – `request`

*Valid only for the `end` position.*

Only pause if requested through the pause request key binding.

<u>Arguments:</u>

`request-replay` — replay from the start of the subtitle after unpausing.

##### – `hide`

Hide the subtitle during playback. Needs to be specified only once per subtitle
track.\
**Note:** Due to an mpv limitation, hiding primary subtitles will always hide
secondary subtitles as well.

Subtitles that do not qualify for a pause will not be hidden.

<u>Arguments:</u>

`hide-more` — hide also while paused for the other subtitle track.

##### – `special`

Also pause on subtitles classified as “special”, for example karaoke subtitles
or subtitles with special positioning that are usually for signs and other text,
not spoken lines.

## Other features

{TODO}

{"toggle" keybinding (default `n`)}

{"replay" keybinding (default `Ctrl-r`)}

{"replay-secondary" keybinding (no default)}

{"request-pause" keybinding (default `MBTN_RIGHT`)}

## Extra options

Besides the setup definition, the script accepts several additional advanced
configuration options. The options should be appended to the same `script-opts`
mpv property used to specify the setup definition.

For example, to specify custom values for the minimum subtitle time duration and
the minimum subtitle text length qualifying for a pause, provide the following
script options to mpv:

```txt
mpv file.mkv --script-opts=sub-pause-setup=start##end,sub-pause-min-sub-duration=2,sub-pause-min-sub-text-length=10
```

### Option list

> **Note:** All options must be additionally prefixed with `sub-pause-`.

– **`min-sub-duration`** (seconds; default: `1`)

Do not pause for subtitles that are programmed to display for less than this
amount of seconds.

– **`min-sub-text-length`** (characters; default: `5`)

Do not pause for subtitles that are shorter than this amount of characters.
(Ignored if the length is equal to `0` to not conflict with image-based
subtitles).

– **`min-pause-duration`** (seconds; default: `0.5`)

If automatic unpausing is enabled, do not pause unless the calculated pause
duration is at least this amount of seconds.

– **`unpause-base`** (seconds; default: `0.4`)

Base automatic pause duration in seconds. Extra pause time dependend on the
length of the subtitle will be a further addition to this value.

– **`unpause-text-multiplier`** (default: `0.0015`)

A multiplier used to transform the subtitle text length in characters into the
auto pause duration in `unpause` mode.

– **`unpause-time-multiplier`** (`0.25`)

A multiplier used to transform the subtitle time length in seconds into the auto
pause duration in `unpause-time` mode.

– **`unpause-exponent`** (`1.8`)

An exponent used to scale the subtitle length (both text and time length,
depending on the mode) in the auto pause duration calculation, so that a
subtitle that is twice as long is, by default, given more than twice the pause
time. To make the scaling linear, set to `1`.