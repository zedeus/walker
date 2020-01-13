import random, sequtils, math, strformat, os, strutils
import flippy, chroma, vmath, cligen, nuuid

type
  Direction = enum
    N, E, S, W,
    NE, SE, SW, NW

  Diagonals = enum
    on, off, only

  State = ref object
    input, output: Image
    tmpFolder: string
    pos: Vec2
    width, height: float
    lastDir: Direction

  Options = object
    input, output: string
    iters: int
    scale, multi, gravity: float
    alpha, threshold: uint8
    invert: bool
    diagonal: Diagonals
    noBacktrack: bool
    frames, fps: int

const
  dirs = @[N, S, E, W]
  dirsDiag = @[NE, SW, SE, NW]
  dirsAll = dirs & dirsDiag

randomize()

proc renderFrame(s: State; frame: int) =
  let file = s.tmpFolder / fmt"{frame:06}.png"
  s.output.save(file)

proc renderAnim(s: State; o: Options) =
  var ffmpeg =
    "ffmpeg -f image2 -i $#/%06d.png -vcodec libx264 -preset fast" &
      " -crf 22 -profile:v baseline -an -movflags +faststart -framerate $#" &
      " -pix_fmt yuvj420p -hide_banner -loglevel panic \"$#\""
  discard execShellCmd(ffmpeg % [s.tmpFolder, $o.fps, o.output])

proc scaleWidth(s: State; scale: float): int =
  result = int(s.width * scale)
  if result mod 2 != 0: result.dec

proc scaleHeight(s: State; scale: float): int =
  result = int(s.height * scale)
  if result mod 2 != 0: result.dec

proc north(s: State; d: float): float = min(s.pos.y + d, s.height)
proc south(s: State; d: float): float = max(s.pos.y - d, 0)
proc east(s: State; d: float): float = min(s.pos.x + d, s.width)
proc west(s: State; d: float): float = max(s.pos.x - d, 0)

proc backtrack(s: State; dir, x, y: Direction): bool =
  dir == x and s.lastDir == y or dir == y and s.lastDir == x

proc `+`(a, b: ColorRGBA): ColorRGBA =
  result.r = min(a.r + b.r, 220'u8)
  result.g = min(a.g + b.g, 220'u8)
  result.b = min(a.b + b.b, 220'u8)
  result.a = 1

proc addLine*(image: var Image, at, to: Vec2, rgba: ColorRGBA) =
  var dx = to.x - at.x
  var dy = to.y - at.y
  var x = at.x
  while true:
    if dx == 0: break
    var y = at.y + dy * (x - at.x) / dx
    var col = image.getRgbaSafe(int x, int y)
    image.putRgbaSafe(int x, int y, col + rgba)
    if at.x < to.x:
      x += 1
      if x > to.x: break
    else:
      x -= 1
      if x < to.x: break

  var y = at.y
  while true:
    if dy == 0: break
    var x = at.x + dx * (y - at.y) / dy
    var col = image.getRgbaSafe(int x, int y)
    image.putRgbaSafe(int x, int y, col + rgba)
    if at.y < to.y:
      y += 1
      if y > to.y: break
    else:
      y -= 1
      if y < to.y: break

proc getWeight(s: State; o: Options; x, y: float): float =
  let color = s.input.getRgba(x, y)
  if not o.invert and color.b > o.threshold: 1.0
  elif   o.invert and color.b < o.threshold: 1.0
  else: o.gravity

proc getPixels(st: State; d: float; o: Options): seq[float] =
  var n, s, e, w, ne, sw, se, nw: float

  if o.diagonal != only:
    n = st.getWeight(o, st.pos.x, st.north(d))
    s = st.getWeight(o, st.pos.x, st.south(d))
    e = st.getWeight(o, st.east(d), st.pos.y)
    w = st.getWeight(o, st.west(d), st.pos.y)

  if o.diagonal == off:
    return @[n, s, e, w]

  ne = st.getWeight(o, st.east(d), st.north(d))
  sw = st.getWeight(o, st.west(d), st.south(d))
  se = st.getWeight(o, st.east(d), st.south(d))
  nw = st.getWeight(o, st.west(d), st.north(d))

  if o.diagonal == only:
    return @[ne, sw, se, nw]
  else:
    return @[n, s, e, w, ne, sw, se, nw]

proc walk(s: State; o: Options) =
  let col = rgba(o.alpha, o.alpha, o.alpha, 1)
  var curFrame, frameMod = 0

  if o.frames > 1:
    frameMod = o.iters div o.frames

  let dirs =
    case o.diagonal
    of off:  dirs
    of on:   dirsAll
    of only: dirsDiag

  for i in 0 ..< o.iters:
    let
      d = rand(1.0 .. o.multi)
      prev = vec2(s.pos.x, s.pos.y)
      weights = getPixels(s, d, o)
      dir = sample(dirs, cumsummed(weights))

    if o.noBacktrack:
      if s.backtrack(dir, N, W): continue
      if s.backtrack(dir, S, E): continue
      if s.backtrack(dir, NE, SW): continue
      if s.backtrack(dir, NW, SE): continue

    s.lastDir = dir

    case dir
    of N, NE, NW: s.pos.y = s.north(d)
    of S, SE, SW: s.pos.y = s.south(d)
    else: discard

    case dir
    of E, NE, SE: s.pos.x = s.east(d)
    of W, NW, SW: s.pos.x = s.west(d)
    else: discard

    s.output.addLine(prev * o.scale, s.pos * o.scale, col)

    if frameMod > 0 and i mod frameMod == 0:
      curFrame.inc
      s.renderFrame(curFrame)

proc main(input, output: string; gravity=20.0; iters=100_000; scale=2.0;
          multi=3.0; alpha=2'u8; threshold=221'u8; invert=false; diagonal=off;
          noBacktrack=true; frames=1; fps=20) =
  let
    o = Options(
      input: input, output: output, gravity: gravity, iters: iters, scale:
      scale, multi: multi, alpha: alpha, invert: invert, threshold: threshold,
      diagonal: diagonal, noBacktrack: noBacktrack, frames: frames, fps: fps)

    temp = loadImage(o.input).minify(o.scale.int)

    state = State(
      input: temp,
      width: float(temp.width - 1),
      height: float(temp.height - 1),
      pos: vec2(rand(temp.width).float, rand(temp.height).float),
      lastDir: N
    )

  if o.frames > 1:
    state.tmpFolder = "/tmp" / generateUUID()
    createDir(state.tmpFolder)

  state.output = newImage(state.scaleWidth(o.scale), state.scaleHeight(o.scale), 3)
  state.walk(o)

  if o.frames > 1:
    doAssert state.tmpFolder.startsWith("/tmp")
    state.renderAnim(o)
    removeDir(state.tmpFolder)
  else:
    state.output.save(o.output)

dispatch(main)
