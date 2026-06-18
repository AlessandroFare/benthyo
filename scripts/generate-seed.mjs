import fs from 'fs';
import { speciesExtra } from './species-extra.mjs';

const diveSites = [
  ['Ustica Secca della Colobbara','ustica-secca-colobbara',38.7100,13.1800,'IT','Sicily',5,45,'advanced','reef','boat'],
  ['Ustica Secca di Punta Gavazzi','ustica-punta-gavazzi',38.6950,13.1750,'IT','Sicily',8,50,'advanced','reef','boat'],
  ['Ustica Grotta dei Gamberi','ustica-grotta-gamberi',38.7000,13.1900,'IT','Sicily',10,35,'intermediate','cave','boat'],
  ['Portofino Christ of the Abyss','portofino-cristo-abissi',44.3167,9.2167,'IT','Liguria',12,18,'beginner','reef','shore'],
  ['Portofino Punta del Faro','portofino-punta-faro',44.3030,9.2100,'IT','Liguria',15,40,'intermediate','wall','boat'],
  ['Elba Pomonte Wreck','elba-pomonte-wreck',42.7450,10.1200,'IT','Tuscany',12,18,'beginner','wreck','shore'],
  ['Elba Scoglietto di Portoferraio','elba-scoglietto',42.8150,10.3200,'IT','Tuscany',5,25,'intermediate','reef','boat'],
  ['Sardinia Tavolara Punta Timi','sardinia-tavolara-timi',40.9100,9.7200,'IT','Sardinia',10,35,'intermediate','wall','boat'],
  ['Sardinia Capo Carbonara','sardinia-capo-carbonara',39.1000,9.5200,'IT','Sardinia',5,30,'beginner','reef','boat'],
  ['Sardinia Nora Roman Ruins','sardinia-nora-ruins',39.0000,9.0100,'IT','Sardinia',3,12,'beginner','reef','shore'],
  ['Lampedusa Secchitello','lampedusa-secchitello',35.5200,12.6100,'IT','Pelagie Islands',15,50,'advanced','pinnacle','boat'],
  ['Lampedusa Tabaccara','lampedusa-tabaccara',35.5000,12.6000,'IT','Pelagie Islands',5,20,'intermediate','reef','boat'],
  ['Pantelleria Grotta di Sataria','pantelleria-sataria',36.8300,11.9500,'IT','Sicily',5,15,'beginner','cave','boat'],
  ['Ischia Secca delle Formiche','ischia-formiche',40.7300,13.9500,'IT','Campania',10,40,'intermediate','reef','boat'],
  ['Procida Vivara Island','procida-vivara',40.7600,14.0200,'IT','Campania',5,25,'beginner','reef','boat'],
  ['Ponza Secca di Frontone','ponza-frontone',40.9100,12.9600,'IT','Lazio',8,35,'intermediate','reef','boat'],
  ['Ventotene Secca di Santo Stefano','ventotene-santo-stefano',40.8000,13.4300,'IT','Lazio',10,45,'advanced','wall','boat'],
  ['Capri Blue Grotto Area','capri-blue-grotto',40.5600,14.2100,'IT','Campania',5,30,'intermediate','cave','boat'],
  ['Sorrento Bagni della Regina','sorrento-bagni-regina',40.6300,14.3800,'IT','Campania',5,20,'beginner','reef','shore'],
  ['Amalfi Li Galli','amalfi-li-galli',40.5500,14.2500,'IT','Campania',15,40,'advanced','wall','boat'],
  ['Cilento Punta Licosa','cilento-licosa',40.2500,14.9000,'IT','Campania',8,30,'intermediate','reef','boat'],
  ['Tremiti San Domino','tremiti-san-domino',42.1200,15.5000,'IT','Puglia',5,35,'intermediate','reef','boat'],
  ['Otranto Punta Palascia','otranto-palascia',40.1300,18.5100,'IT','Puglia',5,25,'beginner','reef','shore'],
  ['Gallipoli Molo di San Andrea','gallipoli-san-andrea',40.0500,17.9900,'IT','Puglia',3,15,'beginner','reef','shore'],
  ['Malta Cirkewwa Reef','malta-cirkewwa',35.9900,14.3300,'MT','Malta',5,30,'beginner','reef','shore'],
  ['Malta Um El Faroud Wreck','malta-um-el-faroud',35.8200,14.5400,'MT','Malta',18,35,'intermediate','wreck','boat'],
  ['Malta Blue Hole Gozo','malta-blue-hole-gozo',36.0550,14.1900,'MT','Gozo',5,40,'intermediate','wall','shore'],
  ['Malta Inland Sea','malta-inland-sea',36.0520,14.1850,'MT','Gozo',5,25,'intermediate','wall','shore'],
  ['Malta Reqqa Point','malta-reqqa-point',36.0800,14.2300,'MT','Gozo',10,45,'advanced','wall','shore'],
  ['Croatia Vis Blue Cave','croatia-vis-blue-cave',43.0500,16.0400,'HR','Vis',5,20,'beginner','cave','boat'],
  ['Croatia Bisevo Blue Cave','croatia-bisevo-blue-cave',42.9800,16.0400,'HR','Vis',5,15,'beginner','cave','boat'],
  ['Croatia Taranto Wreck','croatia-taranto-wreck',43.1700,16.4400,'HR','Hvar',20,42,'advanced','wreck','boat'],
  ['Croatia Premuda Cathedral','croatia-premuda-cathedral',44.3300,14.6000,'HR','Premuda',15,50,'advanced','cave','boat'],
  ['Croatia Kornati Mana','croatia-kornati-mana',43.7900,15.3500,'HR','Kornati',5,35,'intermediate','wall','boat'],
  ['Greece Zakynthos Keri Caves','greece-zakynthos-keri',37.6800,20.8200,'GR','Ionian Islands',5,25,'intermediate','cave','boat'],
  ['Greece Mykonos Paradise Reef','greece-mykonos-paradise',37.4200,25.3500,'GR','Cyclades',5,30,'beginner','reef','boat'],
  ['Greece Santorini Nea Kameni','greece-santorini-nea-kameni',36.4000,25.4000,'GR','Cyclades',10,35,'intermediate','wall','boat'],
  ['Greece Crete Elephant Cave','greece-crete-elephant-cave',35.4200,24.2500,'GR','Crete',8,20,'intermediate','cave','boat'],
  ['Greece Rhodes Anthony Quinn Bay','greece-rhodes-anthony-quinn',36.4400,28.2300,'GR','Dodecanese',5,25,'beginner','reef','shore'],
  ['Spain Medes Islands Tasco Petit','spain-medes-tasco-petit',42.0500,3.2200,'ES','Catalonia',10,35,'intermediate','reef','boat'],
  ['Spain Cabo de Palos Isla Hormiga','spain-cabo-palos-hormiga',37.6300,-0.6800,'ES','Murcia',10,45,'advanced','reef','boat'],
  ['Spain Cabo de Gata La Foradada','spain-cabo-gata-foradada',36.7200,-2.1900,'ES','Andalusia',5,20,'beginner','reef','shore'],
  ['Spain Ibiza Don Pedro Wreck','spain-ibiza-don-pedro',38.8800,1.4200,'ES','Balearic Islands',25,45,'advanced','wreck','boat'],
  ['France Port-Cros La Gabinière','france-port-cros-gabiniere',43.0100,6.3900,'FR','Var',10,40,'intermediate','wall','boat'],
  ['France Cerbère Banyuls Reserve','france-cerbere-banyuls',42.4400,3.1600,'FR','Occitanie',5,30,'intermediate','reef','shore'],
  ['France Marseille Les Catalans','france-marseille-catalans',43.2900,5.3600,'FR','Provence',5,25,'beginner','reef','shore'],
  ['France Nice Cap Ferrat','france-nice-cap-ferrat',43.6900,7.3300,'FR','Alpes-Maritimes',10,35,'intermediate','wall','boat'],
  ['Monaco Larvotto Reserve','monaco-larvotto',43.7500,7.4300,'MC','Monaco',8,30,'intermediate','reef','shore'],
  ['Cyprus Zenobia Wreck','cyprus-zenobia',34.8900,33.6500,'CY','Larnaca',16,42,'advanced','wreck','boat'],
  ['Egypt Ras Mohammed Shark Reef','egypt-ras-mohammed',27.7300,34.2500,'EG','Sinai',5,40,'advanced','wall','boat'],
];

const speciesBase = [
  ['Epinephelus marginatus','Dusky grouper','Cernia bruna','Mero','Serranidae','Epinephelus',492851,274059,273749],
  ['Thalassoma pavo','Ornate wrasse','Tordo pavone','Pez verde','Labridae','Thalassoma',458521,273370,273370],
  ['Sparisoma cretense','Parrotfish','Pesce pappagallo','Pez loro','Scaridae','Sparisoma',458514,273374,273374],
  ['Coris julis','Mediterranean rainbow wrasse','Tordo','Doncella','Labridae','Coris',458475,273368,273368],
  ['Chromis chromis','Damselfish','Castagnola','Castañuela','Pomacentridae','Chromis',458463,273366,273366],
  ['Anthias anthias','Swallowtail seaperch','Anthias','Breca','Serranidae','Anthias',458452,273364,273364],
  ['Sciaena umbra','Brown meagre','Corvina','Corvina','Sciaenidae','Sciaena',492855,274063,274063],
  ['Diplodus sargus','White seabream','Sarago maggiore','Sargo','Sparidae','Diplodus',458468,273367,273367],
  ['Diplodus vulgaris','Two-banded seabream','Sarago comune','Sargo común','Sparidae','Diplodus',458469,273367,273367],
  ['Sarpa salpa','Salema','Salpa','Salpa','Sparidae','Sarpa',458513,273373,273373],
  ['Boops boops','Bogue','Tanuta','Boga','Sparidae','Boops',458456,273365,273365],
  ['Oblada melanura','Saddled seabream','Oblada','Chopa','Sparidae','Oblada',458502,273371,273371],
  ['Pagellus erythrinus','Common pandora','Pagello','Pargo','Sparidae','Pagellus',458505,273372,273372],
  ['Lithognathus mormyrus','Striped seabream','Mormora','Mormora','Sparidae','Lithognathus',458491,273369,273369],
  ['Symphodus tinca','Peacock wrasse','Tordo verde','Doncella','Labridae','Symphodus',458518,273375,273375],
  ['Labrus merula','Brown wrasse','Tordo nero','Doncella','Labridae','Labrus',458487,273368,273368],
  ['Xyrichtys novacula','Pearly razorfish','Pesce luna','Pez ballesta','Labridae','Xyrichtys',458524,273376,273376],
  ['Centrolabrus trutta','Small-mouth wrasse','Tordo piccolo','Doncella','Labridae','Centrolabrus',458461,273366,273366],
  ['Mullus surmuletus','Striped red mullet','Triglia di fango','Salmonete','Mullidae','Mullus',458498,273370,273370],
  ['Mullus barbatus','Red mullet','Triglia','Salmonete','Mullidae','Mullus',458497,273370,273370],
  ['Trachinus draco','Greater weever','Pesce scorpione','Pez araña','Trachinidae','Trachinus',458519,273375,273375],
  ['Uranoscopus scaber','Stargazer','Ragno di mare','Pez rata','Uranoscopidae','Uranoscopus',458521,273376,273376],
  ['Scomber scombrus','Atlantic mackerel','Sgombro','Caballa','Scombridae','Scomber',492860,274068,274068],
  ['Sarda sarda','Atlantic bonito','Palamita','Bonito','Scombridae','Sarda',492858,274066,274066],
  ['Thunnus thynnus','Bluefin tuna','Tonno rosso','Atún rojo','Scombridae','Thunnus',492862,274070,274070],
  ['Belone belone','Garfish','Aguglia','Aguja','Belonidae','Belone',458455,273365,273365],
  ['Fistularia commersonii','Red cornetfish','Fistularia','Pez pipa','Fistulariidae','Fistularia',458471,273367,273367],
  ['Syngnathus abaster','Black-striped pipefish','Pesce ago','Pez pipa','Syngnathidae','Syngnathus',458517,273374,273374],
  ['Hippocampus hippocampus','Short-snouted seahorse','Cavalluccio marino','Caballito de mar','Syngnathidae','Hippocampus',458479,273368,273368],
  ['Octopus vulgaris','Common octopus','Polpo','Pulpo','Octopodidae','Octopus',458503,273371,273371],
  ['Sepia officinalis','Common cuttlefish','Seppia','Sepia','Sepiidae','Sepia',458515,273373,273373],
  ['Sepiola atlantica','Little cuttlefish','Sepiola','Sepiola','Sepiolidae','Sepiola',458516,273373,273373],
  ['Loligo vulgaris','European squid','Calamaro','Calamar','Loliginidae','Loligo',458490,273369,273369],
  ['Eledone moschata','Musky octopus','Polpo muschiato','Pulpo almizclero','Octopodidae','Eledone',458470,273367,273367],
  ['Palinurus elephas','European spiny lobster','Aragosta','Langosta','Palinuridae','Palinurus',458506,273372,273372],
  ['Homarus gammarus','European lobster','Astice','Bogavante','Nephropidae','Homarus',458478,273368,273368],
  ['Scyllarides latus','Mediterranean slipper lobster','Cicale di mare','Cigarra de mar','Scyllaridae','Scyllarides',458512,273373,273373],
  ['Maja squinado','Spinous spider crab','Granchio ragno','Centollo','Majidae','Maja',458492,273369,273369],
  ['Pachygrapsus marmoratus','Marbled rock crab','Granchio di scoglio','Cangrejo','Grapsidae','Pachygrapsus',458504,273371,273371],
  ['Carcinus maenas','Green crab','Granchio verde','Cangrejo verde','Carcinidae','Carcinus',458459,273366,273366],
  ['Paracentrotus lividus','Purple sea urchin','Riccio di mare','Erizo de mar','Parechinidae','Paracentrotus',458505,273372,273372],
  ['Arbacia lixula','Black sea urchin','Riccio nero','Erizo negro','Arbaciidae','Arbacia',458451,273364,273364],
  ['Astroides calycularis','Orange coral','Astroides','Coral naranja','Dendrophylliidae','Astroides',458453,273364,273364],
  ['Paramuricea clavata','Red gorgonian','Gorgonia rossa','Gorgonia roja','Paramuriceidae','Paramuricea',458507,273372,273372],
  ['Eunicella singularis','White gorgonian','Gorgonia bianca','Gorgonia blanca','Gorgoniidae','Eunicella',458472,273367,273367],
  ['Antipathella subpinnata','Yellow black coral','Corallo nero','Coral negro','Myriopathidae','Antipathella',458450,273364,273364],
  ['Cladocora caespitosa','Mediterranean pillow coral','Madrepora a cuscino','Coral cojín','Cladocoridae','Cladocora',458464,273366,273366],
  ['Corynactis viridis','Strawberry anemone','Anemone fragola','Anémona fresa','Corallimorphidae','Corynactis',458466,273366,273366],
  ['Anemonia viridis','Snakelocks anemone','Anemone di mare','Anémona de mar','Actiniidae','Anemonia',458449,273364,273364],
  ['Actinia equina','Beadlet anemone','Anemone rossa','Anémona roja','Actiniidae','Actinia',458448,273364,273364],
];

const speciesMap = new Map();
for (const row of [...speciesBase, ...speciesExtra]) {
  speciesMap.set(row[0], row);
}
const speciesAll = [...speciesMap.values()].slice(0, 200);

const operators = [
  ['Diving Center Ustica','diving-center-ustica','IT','dive_center',38.7050,13.1850,'Via Cristoforo Colombo 12, Ustica','info@divingustica.it','+39 091 844 9001','https://divingustica.it'],
  ['Portofino Divers','portofino-divers','IT','dive_center',44.3035,9.2095,'Via Fondaco 5, Portofino','info@portofinodivers.it','+39 0185 269 012','https://portofinodivers.it'],
  ['Elba Sub','elba-sub','IT','dive_center',42.8145,10.3210,'Via del Molo 3, Portoferraio','info@elbasub.it','+39 0565 918 234','https://elbasub.it'],
  ['Sardinia Dive Experience','sardinia-dive-experience','IT','dive_center',39.1020,9.5180,'Via Molo Umberto I, Villasimius','info@sardiniadive.it','+39 070 792 456','https://sardiniadive.it'],
  ['Scuba Academy Siracusa','scuba-academy-siracusa','IT','dive_center',37.0750,15.2900,'Lungomare Alfeo 22, Siracusa','info@scubaacademy.it','+39 0931 462 88','https://scubaacademy.it'],
];

const badges = [
  ['first-dive','First Splash','Log your first dive in OceanLog','dive_count','{"count":1}',1],
  ['ten-dives','Deco Disciple','Complete 10 logged dives','dive_count','{"count":10}',1],
  ['fifty-dives','Reef Regular','Complete 50 logged dives','dive_count','{"count":50}',2],
  ['hundred-dives','Centurion Diver','Complete 100 logged dives','dive_count','{"count":100}',3],
  ['first-species','Species Spotter','Record your first species sighting','species_count','{"count":1}',1],
  ['twenty-species','Life List Builder','See 20 different species','species_count','{"count":20}',2],
  ['fifty-species','Marine Naturalist','See 50 different species','species_count','{"count":50}',3],
  ['five-sites','Site Explorer','Dive at 5 different sites','site_count','{"count":5}',1],
  ['med-explorer','Mediterranean Explorer','Log a dive in the Mediterranean region','region','{"regions":["mediterranean"]}',2],
  ['group-grouper','Grouper Guardian','Spot a dusky grouper (Epinephelus marginatus)','manual','{"species":"Epinephelus marginatus"}',3],
];

const esc = (s) => String(s).replace(/'/g, "''");

let sql = `-- OceanLog seed data (idempotent)
-- 50 Mediterranean dive sites, 200 marine species, 5 Italian operators, 10 badges

BEGIN;

INSERT INTO dive_sites (name, slug, description, location, country_code, region, depth_min, depth_max, difficulty, site_type, access_type, verified, metadata)
VALUES
${diveSites.map(([name, slug, lat, lng, cc, region, dmin, dmax, diff, type, access]) =>
  `  ('${esc(name)}', '${slug}', 'Popular Mediterranean dive site.', ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography, '${cc}', '${esc(region)}', ${dmin}, ${dmax}, '${diff}', '${type}', '${access}', true, '{"seed": true}'::jsonb)`
).join(',\n')}
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  location = EXCLUDED.location,
  depth_min = EXCLUDED.depth_min,
  depth_max = EXCLUDED.depth_max,
  updated_at = now();

INSERT INTO species (scientific_name, common_name, common_name_it, common_name_es, family, genus, inat_taxon_id, worms_id, gbif_taxon_key, kingdom, metadata)
VALUES
${speciesAll.map(([sci, en, it, es, fam, gen, inat, worms, gbif]) =>
  `  ('${esc(sci)}', '${esc(en)}', '${esc(it)}', '${esc(es)}', '${fam}', '${gen}', ${inat}, ${worms}, ${gbif}, 'Animalia', '{"seed": true}'::jsonb)`
).join(',\n')}
ON CONFLICT (scientific_name) DO UPDATE SET
  common_name = EXCLUDED.common_name,
  common_name_it = EXCLUDED.common_name_it,
  common_name_es = EXCLUDED.common_name_es,
  inat_taxon_id = EXCLUDED.inat_taxon_id,
  worms_id = EXCLUDED.worms_id,
  gbif_taxon_key = EXCLUDED.gbif_taxon_key,
  updated_at = now();

INSERT INTO operators (name, slug, country_code, operator_type, location, address, email, phone, website, subscription_tier, subscription_status, metadata)
VALUES
${operators.map(([name, slug, cc, type, lat, lng, addr, email, phone, web]) =>
  `  ('${esc(name)}', '${slug}', '${cc}', '${type}', ST_SetSRID(ST_MakePoint(${lng}, ${lat}), 4326)::geography, '${esc(addr)}', '${email}', '${phone}', '${web}', 'starter', 'active', '{"seed": true}'::jsonb)`
).join(',\n')}
ON CONFLICT (slug) DO UPDATE SET
  name = EXCLUDED.name,
  email = EXCLUDED.email,
  phone = EXCLUDED.phone,
  website = EXCLUDED.website,
  updated_at = now();

${operators.map(([, slug], idx) => {
  const siteSlug = diveSites[idx][1];
  return `INSERT INTO operator_dive_sites (operator_id, dive_site_id, is_primary)
SELECT o.id, ds.id, true FROM operators o, dive_sites ds
WHERE o.slug = '${slug}' AND ds.slug = '${siteSlug}'
ON CONFLICT (operator_id, dive_site_id) DO UPDATE SET is_primary = EXCLUDED.is_primary;`;
}).join('\n')}

INSERT INTO badges (code, name, description, criteria_type, criteria_value, tier)
VALUES
${badges.map(([code, name, desc, type, val, tier]) =>
  `  ('${code}', '${esc(name)}', '${esc(desc)}', '${type}', '${val}'::jsonb, ${tier})`
).join(',\n')}
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  criteria_type = EXCLUDED.criteria_type,
  criteria_value = EXCLUDED.criteria_value,
  tier = EXCLUDED.tier;

COMMIT;
`;

fs.writeFileSync(new URL('../supabase/seed.sql', import.meta.url), sql);
console.log('Generated seed.sql');
