import {Composition} from 'remotion';
import {Promo, DURATION} from './Promo';

export const Root: React.FC = () => (
  <Composition id="Promo" component={Promo} durationInFrames={DURATION} fps={30} width={1080} height={1920} />
);
