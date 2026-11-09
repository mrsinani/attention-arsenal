import {AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {loadFont} from '@remotion/google-fonts/Outfit';

const {fontFamily} = loadFont('normal', {weights: ['400', '700'], subsets: ['latin']});

export const DURATION = 360; // 12s @ 30fps

// Beats (frames)
const FIRST = 18; // first nudge
const REPEATS = [66, 92]; // "it'll remind you."
const FLOOD_START = 120; // "and again. and again."
const FLOOD_EVERY = 3;
const FLOOD_COUNT = 20;
const CLEAR = 182; // nudges fly away, phone rises
const CLIP_START = 196; // first real frame on screen
const TAP = CLIP_START + 44; // frame 44 of the recording is the tap
const CHECKED = CLIP_START + 48; // frame 48: green check
const END = 276; // end card

const NUDGES = [FIRST, ...REPEATS, ...Array.from({length: FLOOD_COUNT}, (_, i) => FLOOD_START + i * FLOOD_EVERY)];

const BG = '#000';

const Grid: React.FC = () => (
  <AbsoluteFill
    style={{
      backgroundImage:
        'linear-gradient(rgba(255,255,255,.035) 2px,transparent 2px),linear-gradient(90deg,rgba(255,255,255,.035) 2px,transparent 2px)',
      backgroundSize: '90px 90px',
      maskImage: 'linear-gradient(to bottom,#000 0%,#000 60%,transparent 100%)',
    }}
  />
);

const gradientText: React.CSSProperties = {
  background: 'linear-gradient(135deg,#fff 0%,#737373 100%)',
  WebkitBackgroundClip: 'text',
  backgroundClip: 'text',
  color: 'transparent',
  // keep descenders (g, y) inside the painted area
  paddingBottom: '0.2em',
  marginBottom: '-0.2em',
};

/** Caption that springs in at `from` and fades out at `to`. */
const Caption: React.FC<{from: number; to: number; children: React.ReactNode}> = ({from, to, children}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (frame < from || frame > to + 8) return null;
  const enter = spring({frame: frame - from, fps, config: {damping: 200}, durationInFrames: 14});
  const exit = interpolate(frame, [to, to + 8], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div
      style={{
        position: 'absolute',
        top: 250,
        left: 0,
        right: 0,
        textAlign: 'center',
        fontFamily,
        fontWeight: 700,
        fontSize: 96,
        letterSpacing: '-0.035em',
        lineHeight: 1.05,
        color: '#fff',
        opacity: enter * exit,
        transform: `translateY(${(1 - enter) * 40}px)`,
      }}
    >
      {children}
    </div>
  );
};

/** iOS-style banner matching the app's real notification: title "Attention Arsenal", body = task. */
const Nudge: React.FC<{age: string}> = ({age}) => (
  <div
    style={{
      width: 940,
      padding: '30px 34px',
      borderRadius: 54,
      background: 'rgba(44,44,48,0.92)',
      boxShadow: '0 0 0 1.5px rgba(255,255,255,0.06), 0 20px 60px rgba(0,0,0,0.6)',
      display: 'flex',
      alignItems: 'center',
      gap: 28,
      fontFamily: '-apple-system, "SF Pro Text", system-ui, sans-serif',
    }}
  >
    <Img src={staticFile('icon.png')} style={{width: 92, height: 92, borderRadius: 22}} />
    <div style={{flex: 1}}>
      <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'baseline'}}>
        <span style={{fontSize: 36, fontWeight: 600, color: '#fff'}}>Attention Arsenal</span>
        <span style={{fontSize: 30, color: 'rgba(255,255,255,0.5)'}}>{age}</span>
      </div>
      <div style={{fontSize: 36, color: 'rgba(255,255,255,0.88)', marginTop: 4}}>Drink water</div>
    </div>
  </div>
);

const ageLabel = (k: number) => (k === 0 ? 'now' : `${k * 2}m ago`);

/** Newest nudge on top; older ones get pushed down. Floods, then flies off at CLEAR. */
const NudgeStack: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const arrived = NUDGES.filter((f) => f <= frame);
  if (arrived.length === 0 || frame > CLEAR + 20) return null;

  const flood = frame >= FLOOD_START;
  const shake = flood && frame < CLEAR ? Math.sin(frame * 2.1) * 4 : 0;

  return (
    <AbsoluteFill style={{transform: `translateX(${shake}px)`}}>
      {arrived.map((start, i) => {
        const k = arrived.length - 1 - i; // 0 = newest
        const drop = spring({frame: frame - start, fps, config: {damping: 14, mass: 0.6}});
        const slot = 640 + k * 178;
        const y = interpolate(drop, [0, 1], [slot - 120, slot]);
        const scale = interpolate(drop, [0, 1], [0.92, 1]);
        // Leave in a staggered sweep at CLEAR.
        const out = spring({frame: frame - CLEAR - Math.min(k, 10) * 0.6, fps, config: {damping: 200}, durationInFrames: 14});
        const outX = frame >= CLEAR ? out * (k % 2 === 0 ? 1300 : -1300) : 0;
        const tilt = flood ? ((i * 37) % 7) - 3 : 0;
        if (y > 2100) return null;
        return (
          <div
            key={start}
            style={{
              position: 'absolute',
              left: 70,
              top: 0,
              transform: `translate(${outX}px, ${y}px) scale(${scale}) rotate(${tilt * drop}deg)`,
              opacity: drop,
            }}
          >
            <Nudge age={ageLabel(k)} />
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

/** Real screen recording (57 frames), held on the last frame, inside a simple phone frame. */
const Phone: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (frame < CLEAR) return null;
  const rise = spring({frame: frame - CLEAR, fps, config: {damping: 200}, durationInFrames: 20});
  const leave = interpolate(frame, [END - 6, END + 6], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const clipFrame = Math.max(0, Math.min(56, frame - CLIP_START));
  const width = 760;
  const s = width / 1320; // recording px -> phone px
  // Checkbox center in the recording (px), used for the tap ripple.
  const tapX = 98 * s;
  const tapY = 660 * s;
  const ripple = interpolate(frame, [TAP, TAP + 14], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const pad = 18;

  return (
    <div
      style={{
        position: 'absolute',
        left: (1080 - width - pad * 2) / 2,
        top: interpolate(rise, [0, 1], [1950, 560]),
        width: width + pad * 2,
        padding: pad,
        borderRadius: 116,
        background: 'linear-gradient(160deg,#2b2b2e,#0d0d0f 40%,#1c1c1f)',
        boxShadow: '0 0 0 3px #333, 0 0 120px rgba(0,0,0,0.9)',
        opacity: leave,
        transform: `scale(${interpolate(leave, [0, 1], [0.94, 1])})`,
      }}
    >
      <div style={{position: 'relative', borderRadius: 100, overflow: 'hidden'}}>
        <Img src={staticFile(`checkoff/${String(clipFrame).padStart(2, '0')}.png`)} style={{display: 'block', width}} />
        {frame >= TAP && frame <= TAP + 14 ? (
          <div
            style={{
              position: 'absolute',
              left: tapX - 60,
              top: tapY - 60,
              width: 120,
              height: 120,
              borderRadius: '50%',
              background: 'rgba(255,255,255,0.35)',
              transform: `scale(${0.4 + ripple * 0.9})`,
              opacity: 1 - ripple,
            }}
          />
        ) : null}
      </div>
    </div>
  );
};

const EndCard: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (frame < END) return null;
  const pop = (delay: number) => spring({frame: frame - END - delay, fps, config: {damping: 200}, durationInFrames: 16});
  const icon = spring({frame: frame - END, fps, config: {damping: 12, mass: 0.7}});
  const line = (delay: number): React.CSSProperties => ({
    opacity: pop(delay),
    transform: `translateY(${(1 - pop(delay)) * 30}px)`,
  });
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', fontFamily, textAlign: 'center'}}>
      <Img
        src={staticFile('icon.png')}
        style={{width: 280, height: 280, borderRadius: 64, transform: `scale(${icon})`, boxShadow: '0 0 0 2px #262626'}}
      />
      <div style={{...line(8), marginTop: 70, fontSize: 92, fontWeight: 700, letterSpacing: '-0.035em', color: '#fff'}}>
        attention arsenal
      </div>
      <div style={{...line(14), marginTop: 18, fontSize: 60, fontWeight: 700, letterSpacing: '-0.03em'}}>
        <span style={gradientText}>the reminder that never gives up.</span>
      </div>
      <div style={{...line(22), marginTop: 70, fontSize: 44, color: '#a3a3a3'}}>free on the App Store</div>
    </AbsoluteFill>
  );
};

export const Promo: React.FC = () => (
  <AbsoluteFill style={{background: BG}}>
    <Grid />
    <Caption from={4} to={58}>you said you’d do it.</Caption>
    <Caption from={62} to={116}>
      it’ll remind you.
    </Caption>
    <Caption from={FLOOD_START} to={CLEAR - 4}>
      and again.
      <br />
      <span style={gradientText}>and again.</span>
    </Caption>
    <Caption from={CHECKED} to={END - 8}>
      until it’s <span style={gradientText}>done.</span>
    </Caption>
    <NudgeStack />
    <Phone />
    <EndCard />
  </AbsoluteFill>
);
