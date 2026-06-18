import { parseUddfXml } from './uddf.parser';

describe('parseUddfXml', () => {
  it('parses a minimal divesite block', () => {
    const xml = `<?xml version="1.0"?>
<uddf>
  <generator>Shearwater Cloud</generator>
  <diver><dives>
    <site><divesite>
      <name>Blue Hole</name>
      <datetime>2024-06-15T10:30:00</datetime>
      <greatestdepth>32.5</greatestdepth>
      <duration>2400</duration>
      <sample><divetime>60</divetime><depth>10</depth></sample>
    </divesite></site>
  </dives></diver>
</uddf>`;

    const result = parseUddfXml(xml);
    expect(result.dives).toHaveLength(1);
    expect(result.dives[0].siteName).toBe('Blue Hole');
    expect(result.dives[0].diveDate).toBe('2024-06-15');
    expect(result.dives[0].maxDepthM).toBe(32.5);
    expect(result.dives[0].durationMin).toBe(40);
    expect(result.dives[0].profileSamples).toHaveLength(1);
  });
});
