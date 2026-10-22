# Underhum: Steam store text (draft)

A first draft for the store page fields. Valve's review rule: list only what
the game has at launch, or mark future features as planned. Cut anything below
that does not ship.

## Name

Underhum

## Short description

Steam shows this under the header capsule. Keep it under 300 characters.

> A cave gecko with a chameleon's tongue and a mole's knack for digging. Climb
> walls and ceilings, grapple across gaps and chew through rock in a cave where
> every grain of sand, stone and drop of water is simulated.

## About this game

Paste into the Description tab. Valve does not allow links to other websites
in it.

> You are a cave gecko, newly hatched in the dark: sticky feet, a chameleon's
> tongue, and jaws that chew through rock like a mole. The cave around you is
> not a backdrop: every grain of sand, every stone and every drop of water is a
> particle that falls, flows and piles up.
>
> **Every surface is a floor.** Walk up walls and along the ceiling. Squeeze
> your body through cracks barely wider than your head. Swim, and climb out
> dripping.
>
> **A tongue for everything.** Tap to strike, hold to grapple across a gap,
> drag a stone out of the way, or catch a glowing slug and swallow it.
>
> **Dig your own way.** Chew tunnels through soft rock. Bite into a sand bed
> and watch it pour. Roll a boulder into a pit and walk across it. Everything
> you chew fills your stomach, and a full gut has to settle before you can bite
> again.
>
> **A cave that answers back.** Moss you slip off, rock that crumbles under
> your feet, gas pockets that burst, currents that carry you.

## Basic info

- Genres: Indie, Adventure, Casual.
- Developer and publisher: your name or studio name.
- Supported OS: Windows and SteamOS + Linux. The game is made and tested on Linux; turn `BUILD_LINUX` on in `build.sh`. Add macOS only once a Mac build is tested.
- Languages: English, interface only. There is no voice.
- Controller support: none. The game needs a mouse for the tongue and the chew.

## Tags

In order: Steam weighs the first tags most. Up to 20, picked from Steam's own list.

1. Exploration
2. Physics
3. Cute
4. Atmospheric
5. Pixel Graphics
6. 2D Platformer
7. Destruction
8. Underground
9. Nature
10. Relaxing
11. Singleplayer
12. 2D
13. Adventure
14. Casual
15. Indie
16. Sandbox
17. Climbing, if Steam's list has it
18. Swimming, if Steam's list has it
19. Procedural Generation, only if the shipped caves are generated

## Content survey: generative AI

Steam's question covers the build, the store page and marketing. Decided
2026-10-22: answer **No** while the prototype is a store page only. That holds
only while nothing AI-made is on the page or on Steam:

- Screenshots, GIFs and the trailer must not show the Retro Diffusion decor:
  everything in `decor/stamps/` (shrooms, moss, ferns, plants, tall plants,
  vine leaves) and the gecko's curl and wake sprites in `decor/gecko/wake/`.
  The metaball gecko and the simulated cave are not AI.
- No build that still packs those files goes to Steam (no playtest, no demo).
  `export_presets.cfg` includes both folders.

The final art will be made by an artist. If any of the above changes first,
publish a new survey version with Yes and this disclosure:

> Some decor sprites (mushrooms, plants, vines and moss) and the gecko's
> sleep and wake animation began as images made with Retro Diffusion, an AI
> pixel-art tool, and were cleaned and recoloured with our own tools. They are
> placeholders for artist-made art. No content is generated while the game
> runs.
