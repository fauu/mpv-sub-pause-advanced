<!-- vim: set textwidth=80 colorcolumn=80: -->
<!-- markdownlint-configure-file
{
  "line-length": { "code_blocks": false },
  "no-inline-html": false,
  "fenced-code-language": false
}
-->
# mpv-sub-pause-advanced

> A versatile [mpv] media player script for pausing video playback for subtitles

<!-- -->

> **Warning**
> This script has not been thoroughly tested yet with all of its possible
> configuration combinations. Please feel encouraged to report any suspected
> issues / incompatibilities / unexpected behaviours by creating a
> [Github issue][issues].

[issues]: https://github.com/fauu/mpv-sub-pause-advanced/issues
[mpv]: https://mpv.io/

## Main features

* Independently set up pausing at the start/end of the primary/secondary
  subtitle track.

* Automatically unpause after a time period dependent on the subtitle
  length (text length or time duration).

* Pause on request: press a key to request a pause at the end of the current
  subtitle.

* Skip pausing for subtitles below a specified length threshold.

* Skip pausing for special subtitles, such as karaoke subtitles or sign
  subtitles.

* Hide a subtitle while playing or when paused for another subtitle track.

## Table of contents

1. [Installation](#installation)
2. [Basic usage](#basic-usage)
3. [The setup definition](#the-setup-definition)
    * [Form](#form)
    * [All setup parameters](#all-setup-parameters)
4. [Key bindings](#key-bindings)
5. [Extra options](#extra-options)
    * [Option list](#option-list)
6. [Known issues](#known-issues)
7. [Credits](#credits)

## Installation

Download the [script file] (click on the `Raw` button and then press
<kbd>Ctrl</kbd> + <kbd>S</kbd>), placing it in the `scripts` subdirectory of the
mpv configuration directory (see [Script location][mpv-script-location] in mpv
manual).

[mpv-script-location]: https://mpv.io/manual/stable/#script-location
[script file]: https://github.com/fauu/mpv-sub-pause-advanced/blob/master/sub-pause-advanced.lua
[script file]: https://raw.githubusercontent.com/fauu/mpv-sub-pause-advanced/master/sub-pause-advanced.lua

## Basic usage

To enable the script, provide a setup definition as a script option to mpv. Here
is an illustration of different ways to provide the setup definition `2end`, which
instructs the script to pause at the end of each *secondary* subtitle:

1. Directly when launching mpv:

    ```sh
    mpv file.mkv --script-opts=sub-pause-setup=2end
    ```

1. Globally in [mpv config]:

    ```
    script-opts=sub-pause-setup=2end
    ```

1. As a [custom profile] in mpv config:

    ```
    [my-sub-pause-profile]
    script-opts=sub-pause-setup=2end
    ```

    then enable electively when starting mpv:

    ```sh
    mpv file.mkv --profile=my-sub-pause-profile
    ```

[mpv config]: https://mpv.io/manual/stable/#configuration-files
[custom profile]: https://mpv.io/manual/stable/#profiles

---

> **Note**
> **By default, pausing will be skipped when the subtitle does not met certain
> conditions:**
>
> 1. The subtitle’s time duration is below the default threshold.
>
> 1. The subtitle’s text length is above zero but below the default threshold.
>
> 1. Auto unpause is enabled and the subtitle’s calculated pause duration is
>    below the default threshold.
>
> The values of these defaults and the way to override them are described in the
> section [Extra options](#extra-options).

## The setup definition

### Form

The setup definition is a string of characters that tells the script when to
pause and how to do it. It consists of up to four *parts* separated with the
characters `##`. Those parts each define a pause point in one of four available
positions: start of primary subtitle, end of primary subtitle, start of
secondary subtitle, end of secondary subtitle.

For example, the following definition enables pause at the start of the
secondary subtitle and at the end of the primary subtitle:

```
2start##end
```

Furthermore, each of the parts can be modified with extra configuration
directives separated with the `!` character. For example, to extend the
above definition with the options:

1. Hide the secondary subtitle while playing.

1. Once paused at the end of a primary subtitle, wait a bit and then
  automatically unpause.

the following setup definition should be specified:

```
2start!hide##end!unpause
```

Multiple directives can be provided within a single *part*. For example, to make
it so that, on top of the previous configuration, the pause at the end of a
primary subtitle only happens if a specified pause request key is pressed before
the end of the subtitle is reached, the definition should read:

```
2start!hide##end!unpause!request
```

Finally, some directives can have extra arguments, separated with the `-`
character, that additionally modify their behaviour. For example, to prolong the
interval before the automatic unpause for the end of a primary subtitle by
a factor of 1.5, specify:

```
2start!hide##end!unpause-1.5!request
```

### All setup parameters

#### Pause position specifiers

`start` — start of each primary subtitle.

`end` — end of each primary subtitle.

`2start` — start of each secondary subtitle.

`2end` — end of each secondary subtitle.

#### Directives

##### – `unpause`

Automatically unpause after a time interval calculated on the basis of the
subtitle text length. Note that this will not work properly for image-based
subtitled—for those, the `-time` argument must be used.

<ins>Arguments:</ins>

`unpause-time` — calculate the unpause interval based on the subtitle’s defined
playback time instead.

`unpause[-time]-<number>` — multiply the calculated unpause interval by
`<number>`. Supports decimal parts, for example `0.75`.

Advanced modifications to the calculation formula can be made through [Extra
options](#extra-options).

##### – `request`

> *Valid only for the `end` position.*

Only pause if requested through the pause request key binding (see [Key
bindings](#key-bindings)).

<ins>Arguments:</ins>

`request-replay` — after unpause, replay from the start of the subtitle.

##### – `hide`

Hide the subtitle during playback, unless it does not qualify for a pause.
(Only needs to be specified once per subtitle track.)

> **Warning**
> In mpv 0.34 and earlier, hiding primary subtitles hides secondary subtitles as
> well.

<ins>Arguments:</ins>

`hide-more` — hide also while paused for the other subtitle track.

##### – `race`

> *Valid only for the `end` position.*

Skip pause to avoid two consecutive pauses in case when we just recently paused
for the end of the subtitle on the other track. In other words, the following
setup definition:

```
end!race##2end!race
```

provided the two subtitle tracks are reasonably synchronized, should lead to
only one pause at the end of each subtitled line, at time position dependent on
whichever track has its subtitle ending earlier.

The playback time interval, counting from the previous pause, within which this
skip is active, can be customized through the [extra option](#extra-options)
`pair-sub-max-delta`.

##### – `special`

Also pause on subtitles classified as “special”, for example karaoke subtitles
or subtitles with special positioning that are usually for signs and other text,
not spoken lines.

## Key bindings

Below is a list of key bindings available for the script. To assign a key where
none is assigned by default or to assign a different one, add an appropriate
`script-binding` line to mpv’s [input.conf] file.

For example, to have the key <kbd>N</kbd> (i.e., <kbd>Shift</kbd> + <kbd>n</kbd>)
turn the script off and back on, add the line:

```
N script-binding sub_pause_advanced/toggle-pausing
```

(Note the underscores.)

To set other bindings, replace, in the example above, `N` with the desired key
(see [Key names] in mpv manual) and `toggle-pausing` with the name of one of
the other bindings listed below.

– **`toggle-pausing`** (default: none; recommendation: <kbd>N</kbd>)

Disable or re-enable pausing and adjacent features (such as subtitle hiding).

– **`override-pausing`** (default: none; recommendation: <kbd>n</kbd>)

Unpause and prevent any pauses *while the key remains pressed*.

– **`request-pause`** (default: none; recommendation: <kbd>MBTN_RIGHT</kbd>)

When the `request` directive is active, queue a pause for the end of the current
subtitle. Otherwise, pause immediately. If already paused—unpause.

– **`replay`** (default: <kbd>Ctrl</kbd> + <kbd>r</kbd>)

Replay from the start of the current or previous primary subtitle.

– **`replay-secondary`** (default: none)

Replay from the start of the current or previous secondary subtitle.

[input.conf]: https://mpv.io/manual/stable/#input-conf
[Key names]: https://mpv.io/manual/stable/#key-names

## Extra options

Besides the setup definition, the script accepts several additional advanced
configuration options. The options should be appended to the same `script-opts`
mpv property that is used to specify the setup definition.

For example, to specify custom values for the minimum subtitle time duration and
the minimum subtitle text length qualifying for a pause, provide the following
script options to mpv:

```
mpv file.mkv --script-opts=sub-pause-setup=start##end,sub-pause-min-sub-duration=2,sub-pause-min-sub-text-length=10
```

### Option list

> **Note**
> All options must be additionally prefixed with `sub-pause-`.

– **`min-sub-duration`** (seconds; default: `1`)

Do not pause for subtitles that are programmed to display for less than this
amount of seconds.

– **`min-sub-text-length`** (characters; default: `5`)

Do not pause for subtitles that are shorter than this amount of characters.
(Ignored if the length is equal to `0` to not include all image-based
subtitles).

– **`min-pause-duration`** (seconds; default: `0.5`)

If [`unpause`](#directives) is enabled, do not pause unless the calculated pause
duration is at least this amount of seconds.

– **`unpause-base`** (seconds; default: `0.4`)

Base automatic pause duration in seconds. Extra pause time dependent on the
length of the subtitle will be a further addition to this base value.

– **`unpause-text-multiplier`** (default: `0.017`)

A multiplier used to transform the subtitle text length in characters into the
auto pause duration in `unpause` mode.

– **`unpause-time-multiplier`** (`0.57`)

A multiplier used to transform the subtitle time length in seconds into the auto
pause duration in `unpause-time` mode.

– **`unpause-exponent`** (`1.2`)

An exponent used to scale the subtitle length (both text and time length,
depending on the mode) in the auto pause duration calculation, so that a
subtitle that is twice as long is, by default, given more than twice the pause
time. To make the scaling linear, set to `1`.

– **`pair-sub-max-delta`** (`0.9`)

If [`race`](#directives) is enabled, do not pause in case when we already paused
for subtitle end on the other track at most this many seconds ago (in terms of
video playback time).

– **`sub-delay`** (`no`)

If a number is provided, set the mpv sub delay to that many seconds each time
the script is initialized with at least one pause point set up.

## Known issues

**I. Not pausing when there is an overlapping sign subtitle present during
dialogue lines**

Most likely impossible to fix for the `end` position, because in this case we
receive a `sub-end` event only for the sign subtitle, and not for the dialogue
subtitles that change while the sign subtitle is present.

We do, however, receive separate `sub-text` events. This could be used to make
the `start` position work. But it would only work for text-based subtitles and
would therefore have to be implemented as an extra special case, which probably
is not worth the extra complexity.

<ins>Reproduction:</ins> *Hanasaku Iroha - E15* (Doki) `sub-pause-setup=start --start=2:00`

## Credits

Inspired by [sub-pause] from @Ben-Kerman.

[sub-pause]: https://github.com/Ben-Kerman/mpv-sub-scripts/
