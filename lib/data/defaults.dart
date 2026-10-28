/// Categorie, icone e regole predefinite: le stesse della versione web.
library;

class DefaultCategory {
  const DefaultCategory(this.name, this.kind, this.color, this.icon);
  final String name;
  final String kind; // expense | income | transfer
  final String color;
  final String icon;
}

const defaultCategories = [
  DefaultCategory('Spesa alimentare', 'expense', '#2a9d8f', 'shopping-cart'),
  DefaultCategory('Ristoranti e bar', 'expense', '#e76f51', 'tools-kitchen-2'),
  DefaultCategory('Trasporti', 'expense', '#457b9d', 'bus'),
  DefaultCategory('Carburante', 'expense', '#6c757d', 'gas-station'),
  DefaultCategory('Casa e utenze', 'expense', '#8d6e63', 'home-bolt'),
  DefaultCategory('Abbonamenti', 'expense', '#9c27b0', 'device-tv'),
  DefaultCategory('Shopping', 'expense', '#f4a261', 'shopping-bag'),
  DefaultCategory('Salute', 'expense', '#43aa8b', 'heart-plus'),
  DefaultCategory('Svago e viaggi', 'expense', '#277da1', 'plane'),
  DefaultCategory('Contanti', 'expense', '#90be6d', 'cash'),
  DefaultCategory('Commissioni bancarie', 'expense', '#bc4749', 'building-bank'),
  DefaultCategory('Altre spese', 'expense', '#adb5bd', 'receipt'),
  DefaultCategory('Stipendio', 'income', '#2b9348', 'briefcase'),
  DefaultCategory('Altre entrate', 'income', '#80b918', 'coin'),
  DefaultCategory('Giroconti', 'transfer', '#ced4da', 'arrows-exchange'),
];

const defaultIcon = 'tag';

/// Icone che si possono scegliere per una categoria (pagina Categorie).
const iconChoices = [
  'shopping-cart', 'tools-kitchen-2', 'coffee', 'pizza', 'bus', 'car', 'gas-station',
  'train', 'bike', 'plane', 'beach', 'home', 'home-bolt', 'bolt', 'droplet', 'wifi',
  'device-mobile', 'device-tv', 'device-gamepad-2', 'music', 'movie', 'ticket',
  'shopping-bag', 'shirt', 'gift', 'heart-plus', 'pill', 'stethoscope', 'barbell',
  'school', 'book', 'paw', 'baby-carriage', 'users', 'tool', 'credit-card',
  'building-bank', 'cash', 'coin', 'pig-money', 'briefcase', 'receipt',
  'arrows-exchange', 'chart-line', 'tag',
];

/// Categoria degli investimenti (es. acquisti di titoli): soldi spostati sul
/// conto titoli, quindi risparmio e non spesa. Si assegna solo a mano.
const investmentCategory = DefaultCategory('Investimenti', 'expense', '#4361ee', 'chart-line');

/// Regola creata dalla prima versione degli Investimenti e poi tolta: l'utente
/// sceglie a mano quali movimenti sono investimenti.
const removedInvestmentRule = 'compravendita titoli';

/// Le regole predefinite si aggiungono una volta per versione: quelle che hai
/// eliminato a mano non ricompaiono.
const defaultRulesVersion = 3;

/// Da aumentare quando cambia il modo di riconoscere giroconti/categorie:
/// all'avvio i movimenti vengono ricalcolati (senza toccare le regole).
const classifierVersion = 4;

const defaultRules = <String, Map<String, List<String>>>{
  'Spesa alimentare': {
    'text': ['esselunga', 'coop', 'conad', 'carrefour', 'lidl', 'eurospin',
      'despar', 'aldi', 'penny', 'pam ', 'iper', 'bennet', 'tigros',
      'mercadona', 'hemkop', 'ica ', ' spar ', 'market',
      'supermerc', 'panificio', 'forno', 'macelleria', 'frutta'],
    'mcc': ['5411', '5412', '5499'],
  },
  'Ristoranti e bar': {
    'text': ['mcdonald', 'burger king', 'ristorante', 'pizzeria', 'trattoria',
      'deliveroo', 'glovo', 'just eat', 'starbucks', 'caffe', 'bar ',
      'mc donald', 'gelateria', 'pasticceria', 'torrefazione',
      'osteria', 'pub ', 'kebab', 'sushi'],
    'mcc': ['5812', '5813', '5814'],
  },
  'Trasporti': {
    'text': ['trenitalia', 'italo', 'atm milano', 'uber', 'free now',
      'ryanair', 'easyjet', 'wizz', 'ita airways', 'telepass',
      'autostrade', 'flixbus'],
    'mcc': ['4111', '4121', '4131', '4511', '4784', '4789'],
  },
  'Carburante': {
    'text': ['enilive', 'q8', 'tamoil', 'esso', 'shell', 'agip'],
    'mcc': ['5541', '5542'],
  },
  'Casa e utenze': {
    'text': ['enel', 'a2a', 'iren', 'hera', 'edison', 'tim ', 'vodafone',
      'iliad', 'fastweb', 'windtre', 'affitto'],
    'mcc': ['4900', '4814'],
  },
  'Abbonamenti': {
    'text': ['netflix', 'spotify', 'disney', 'amazon prime', 'apple.com',
      'icloud', 'youtube', 'dazn', 'google one', 'chatgpt', 'openai',
      'anthropic', 'claude.ai'],
    'mcc': [],
  },
  'Shopping': {
    'text': ['amazon', 'zalando', 'ikea', 'decathlon', 'zara', 'h&m',
      'mediaworld', 'unieuro'],
    'mcc': ['5311', '5651', '5691', '5732'],
  },
  'Salute': {
    'text': ['farmacia', 'parafarmacia', 'dentist', 'ospedale'],
    'mcc': ['5912', '8011', '8021', '8062', '8099'],
  },
  'Svago e viaggi': {
    'text': ['booking.com', 'airbnb', 'cinema', 'uci ', 'steam', 'playstation',
      'ticketone', 'museo', 'museum', 'museet', 'hotel'],
    'mcc': ['7011', '7832', '4722', '7922', '7991'],
  },
  'Contanti': {
    'text': ['prelievo', 'atm withdrawal', 'cash withdrawal'],
    'mcc': ['6011'],
  },
  'Commissioni bancarie': {
    'text': ['commissione', 'canone', 'imposta di bollo'],
    'mcc': [],
  },
  'Stipendio': {
    'text': ['stipendio', 'salary', 'emolumenti', 'retribuzione'],
    'mcc': [],
  },
};
