const fs = require('node:fs');

const escape = value => String(value).replace(/[&<>"']/g, ch => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
})[ch]);

function render(lesson) {
  const drills = [lesson.first, lesson.second].map(drill =>
    '<li><h2>' + escape(drill.name) + '</h2><p>' + escape(drill.target)
    + '</p><p><strong>Criterio:</strong> ' + escape(drill.success) + '</p></li>'
  );
  return '<!DOCTYPE html><html lang="it"><meta charset="utf-8"><title>'
    + escape(lesson.title) + '</title><main><h1>' + escape(lesson.title)
    + '</h1><p>' + escape(lesson.goal) + '</p><ol>' + drills.join('')
    + '</ol></main></html>\n';
}
module.exports = { render };
if (require.main === module) process.stdout.write(render(JSON.parse(fs.readFileSync(0, 'utf8'))));
