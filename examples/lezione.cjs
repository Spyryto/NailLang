const drill = (name, target, success) => ({ name, target, success });

module.exports = {
  title: 'Bending intonato',
  goal: 'Arrivare alla nota bersaglio senza superarla',
  first: drill(
    'Ascolta e ripeti',
    'Suona prima la nota bersaglio, poi fai il bending',
    '4 arrivi intonati su 5'
  ),
  second: drill(
    'Ripeti a tempo',
    'Fai un bending ogni due battiti a 60 BPM',
    '4 arrivi intonati su 5 senza perdere il tempo'
  )
};
