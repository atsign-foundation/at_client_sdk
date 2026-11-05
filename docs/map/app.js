// Draws the SDK map from window.MAP and the flow files data/flows/<id>.js.
// Every piece of text reaches the page through textContent, and every link
// passes safeHref first.
(function () {
  'use strict';

  var SVG = 'http://www.w3.org/2000/svg';
  var MAP = window.MAP;
  window.MAP_FLOWS = window.MAP_FLOWS || {};

  var LANE_HEAD = 104;
  var ROW = 76;
  var BOX_H = 52;
  var SERVER_W = 210;
  var SUBLANE_W = 150;

  var state = { flow: null, step: null };

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined && text !== null) e.textContent = String(text);
    return e;
  }

  function svg(tag, attrs, text) {
    var e = document.createElementNS(SVG, tag);
    Object.keys(attrs || {}).forEach(function (k) {
      e.setAttribute(k, String(attrs[k]));
    });
    if (text !== undefined && text !== null) e.textContent = String(text);
    return e;
  }

  // A path inside this repository, two levels up from docs/map, or a page
  // under https://github.com/atsign-foundation/.
  function safeHref(href) {
    if (typeof href !== 'string') return null;
    if (/^https:\/\/github\.com\/atsign-foundation\/[A-Za-z0-9_.\/#%:@+=~-]+$/.test(href) &&
        href.indexOf('..') < 0) {
      return href;
    }
    if (/^\.\.\/\.\.\/[A-Za-z0-9_][A-Za-z0-9_.\/-]*(#L\d+(-L\d+)?)?$/.test(href) &&
        href.slice(6).indexOf('..') < 0) {
      return href;
    }
    return null;
  }

  function repoHref(path) {
    return safeHref(/^https:/.test(path) ? path : '../../' + path);
  }

  function link(href, text) {
    var safe = safeHref(href);
    if (!safe) return el('span', 'refused-link', text);
    var a = el('a', null, text);
    a.setAttribute('href', safe);
    if (/^https:/.test(safe)) a.setAttribute('rel', 'noopener noreferrer');
    return a;
  }

  function parseHash() {
    var out = {};
    location.hash.replace(/^#/, '').split('&').forEach(function (part) {
      var i = part.indexOf('=');
      if (i > 0) out[part.slice(0, i)] = decodeURIComponent(part.slice(i + 1));
    });
    return out;
  }

  function setHash(flow, step) {
    var h = '#flow=' + encodeURIComponent(flow) +
        (step ? '&step=' + encodeURIComponent(step) : '');
    if (location.hash !== h) location.hash = h;
  }

  function loadScript(src, done) {
    var s = document.createElement('script');
    s.src = src;
    s.onload = function () { done(true); };
    s.onerror = function () { done(false); };
    document.head.appendChild(s);
  }

  var indexesRequested = false;
  function loadIndexes(done) {
    if (window.MAP_INDEXES || indexesRequested) { done(); return; }
    indexesRequested = true;
    loadScript('data/indexes.js', function () { done(); });
  }

  function laneById(id) {
    for (var i = 0; i < MAP.lanes.length; i++) {
      if (MAP.lanes[i].id === id) return MAP.lanes[i];
    }
    return { id: id, title: id, role: 'client', sublanes: [] };
  }

  function renderLenses() {
    var nav = document.getElementById('lenses');
    nav.textContent = '';
    MAP.lenses.forEach(function (lens) {
      var box = el('div', 'lens');
      box.appendChild(el('h3', null, lens.title));
      box.appendChild(el('p', null, lens.summary));
      var ul = el('ul');
      lens.flows.forEach(function (id) {
        var li = el('li');
        var flow = MAP.flows.filter(function (f) { return f.id === id; })[0];
        var a = el('a', null, flow ? flow.title : id);
        a.setAttribute('href', '#flow=' + encodeURIComponent(id));
        li.appendChild(a);
        ul.appendChild(li);
      });
      (lens.links || []).forEach(function (l) {
        var li = el('li', 'lens-link');
        li.appendChild(link(repoHref(l.href), l.title));
        ul.appendChild(li);
      });
      box.appendChild(ul);
      nav.appendChild(box);
    });
  }

  function columns(flow) {
    var cols = [];
    var x = 0;
    flow.lanes.forEach(function (id) {
      var lane = laneById(id);
      var subs = lane.role === 'client' && lane.sublanes.length ? lane.sublanes : [null];
      var w = lane.role === 'client' ? subs.length * SUBLANE_W : SERVER_W;
      cols.push({ lane: lane, x: x, w: w, subs: subs });
      x += w;
    });
    return { cols: cols, width: x };
  }

  function boxFor(layout, step, row) {
    var col = layout.cols.filter(function (c) { return c.lane.id === step.lane; })[0];
    var sub = Math.max(0, col.subs.indexOf(step.sublane || null));
    var w = col.subs.length > 1 ? SUBLANE_W : col.w;
    var x = col.x + sub * (col.subs.length > 1 ? SUBLANE_W : 0) + 8;
    return { x: x, y: LANE_HEAD + row * ROW + 12, w: w - 16, h: BOX_H };
  }

  function wrap(text, width) {
    var words = text.split(' ');
    var lines = [];
    var line = '';
    words.forEach(function (w) {
      if (line && (line + ' ' + w).length > width) {
        lines.push(line);
        line = w;
      } else {
        line = line ? line + ' ' + w : w;
      }
    });
    if (line) lines.push(line);
    return lines;
  }

  function arrowLabel(r) {
    if (!r) return '';
    if (r.kind === 'wire') return (r.text || 'wire').replace(/,.*$/, '');
    if (r.kind === 'field' || r.kind === 'stream') return r.kind + ' hop';
    if (r.kind === 'declared') return 'declared hop';
    if (r.kind === 'untraced') return 'via (untraced)';
    return r.kind;
  }

  function renderDiagram(flow) {
    var host = document.getElementById('diagram');
    host.textContent = '';
    var layout = columns(flow);
    var height = LANE_HEAD + flow.steps.length * ROW + 24;
    var root = svg('svg', {
      'class': 'flow', width: layout.width, height: height,
      viewBox: '0 0 ' + layout.width + ' ' + height, role: 'img',
      'aria-label': flow.title
    });
    var defs = svg('defs');
    var marker = svg('marker', {
      id: 'arrow', viewBox: '0 0 10 10', refX: 9, refY: 5,
      markerWidth: 7, markerHeight: 7, orient: 'auto-start-reverse'
    });
    marker.appendChild(svg('path', { d: 'M 0 0 L 10 5 L 0 10 z', 'class': 'arrowhead' }));
    defs.appendChild(marker);
    root.appendChild(defs);

    layout.cols.forEach(function (c) {
      var g = svg('g', { 'class': 'lane lane-' + c.lane.role, 'data-lane': c.lane.id });
      g.appendChild(svg('rect', { x: c.x, y: 0, width: c.w, height: height, 'class': 'lane-bg' }));
      g.appendChild(svg('text', { x: c.x + 10, y: 22, 'class': 'lane-title' }, c.lane.title));
      g.appendChild(svg('text', { x: c.x + 10, y: 38, 'class': 'lane-id' }, c.lane.id));
      if (c.lane.role === 'server' && flow.laneNote) {
        var note = svg('text', { x: c.x + 10, y: 56, 'class': 'lane-note' });
        var lines = wrap(flow.laneNote, 30);
        lines.forEach(function (line, i) {
          note.appendChild(svg('tspan', { x: c.x + 10, dy: i === 0 ? 0 : 13 },
              i < lines.length - 1 ? line + ' ' : line));
        });
        g.appendChild(note);
      }
      if (c.subs.length > 1) {
        c.subs.forEach(function (s, i) {
          var sx = c.x + i * SUBLANE_W;
          if (i > 0) {
            g.appendChild(svg('line', { x1: sx, y1: 50, x2: sx, y2: height, 'class': 'sublane-rule' }));
          }
          g.appendChild(svg('text', { x: sx + 10, y: 62, 'class': 'sublane-title' }, s));
        });
      }
      root.appendChild(g);
    });

    var rows = {};
    flow.steps.forEach(function (s, i) { rows[s.id] = i; });

    (flow.frames || []).forEach(function (f) {
      var top = LANE_HEAD + rows[f.from] * ROW + 2;
      var bottom = LANE_HEAD + (rows[f.to] + 1) * ROW - 2;
      var g = svg('g', { 'class': 'frame frame-' + f.kind });
      g.appendChild(svg('rect', { x: 2, y: top, width: layout.width - 4, height: bottom - top }));
      g.appendChild(svg('text', { x: 8, y: top + 11, 'class': 'frame-label' }, f.kind + ': ' + f.label));
      root.appendChild(g);
    });

    flow.steps.forEach(function (s, i) {
      var r = s.reached || {};
      if (i === 0 || r.kind === 'entry') return;
      var from = r.from ? rows[r.from] : i - 1;
      var a = boxFor(layout, flow.steps[from], from);
      var b = boxFor(layout, s, i);
      var x1 = a.x + a.w / 2;
      var y1 = a.y + a.h;
      var x2 = b.x + b.w / 2;
      var y2 = b.y;
      var g = svg('g', { 'class': 'edge edge-' + (r.kind || 'call') });
      g.appendChild(svg('path', {
        d: 'M ' + x1 + ' ' + y1 + ' C ' + x1 + ' ' + (y1 + 18) + ', ' + x2 + ' ' + (y2 - 18) + ', ' + x2 + ' ' + y2,
        'marker-end': 'url(#arrow)'
      }));
      g.appendChild(svg('text', { x: (x1 + x2) / 2 + 6, y: (y1 + y2) / 2 + 4, 'class': 'edge-label' }, arrowLabel(r)));
      root.appendChild(g);
    });

    flow.steps.forEach(function (s, i) {
      var b = boxFor(layout, s, i);
      var amber = s.changed && laneById(s.lane).role === 'client';
      var g = svg('g', {
        'class': 'step' + (amber ? ' amber' : ''),
        'data-step': s.id, tabindex: 0, role: 'button',
        'aria-label': s.id + ': ' + s.intent
      });
      g.appendChild(svg('rect', { x: b.x, y: b.y, width: b.w, height: b.h, rx: 6 }));
      g.appendChild(svg('text', { x: b.x + 8, y: b.y + 20, 'class': 'step-id' }, s.id));
      g.appendChild(svg('text', { x: b.x + 8, y: b.y + 38, 'class': 'step-symbol' },
          s.anchor ? s.anchor.symbol.replace(/^.*\./, '') : ''));
      if (amber) {
        g.appendChild(svg('text', { x: b.x + b.w - 8, y: b.y + 20, 'class': 'amber-mark', 'text-anchor': 'end' }, 'changed'));
      }
      g.addEventListener('click', function () { setHash(flow.id, s.id); });
      g.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          setHash(flow.id, s.id);
        }
      });
      root.appendChild(g);
    });
    host.appendChild(root);
  }

  function section(panel, title) {
    var s = el('section', 'panel-section');
    s.appendChild(el('h4', null, title));
    panel.appendChild(s);
    return s;
  }

  function evidenceFor(flowId, stepId, exitId) {
    var ix = window.MAP_INDEXES;
    if (!ix) return null;
    var f = ix.flows && ix.flows[flowId];
    var s = f && f.steps && f.steps[stepId];
    return s && s.exits ? s.exits[exitId] || null : null;
  }

  function backingNode(b) {
    var span = el('span', 'backing');
    if (b.exit) {
      span.appendChild(document.createTextNode('exit '));
      span.appendChild(el('code', null, b.exit.guard));
      span.appendChild(document.createTextNode(' in '));
      span.appendChild(b.exit.url ? link(b.exit.url, b.exit.symbol) : el('code', null, b.exit.symbol));
    } else if (b.gherkin) {
      span.appendChild(document.createTextNode('scenario "'));
      span.appendChild(el('span', 'scenario-title', b.gherkin.scenario));
      span.appendChild(document.createTextNode('", clause "'));
      span.appendChild(el('span', 'clause', b.gherkin.clause));
      span.appendChild(document.createTextNode('" in '));
      span.appendChild(link(b.gherkin.url, b.gherkin.feature));
    }
    return span;
  }

  function renderPanel(flow, step) {
    var panel = document.getElementById('panel');
    panel.textContent = '';
    if (!step) {
      panel.appendChild(el('p', 'hint', 'Select a step to see what it does and where.'));
      return;
    }
    var lane = laneById(step.lane);
    panel.appendChild(el('h3', 'panel-title', flow.id + '.' + step.id));
    panel.appendChild(el('p', 'panel-lane', lane.title + (step.sublane ? ' / ' + step.sublane : '')));
    panel.appendChild(el('p', 'panel-intent', step.intent)).id = 'panel-intent';
    if (step.changed && lane.role === 'client') {
      panel.appendChild(el('p', 'amber-note', 'Code changed since it was reviewed.')).id = 'panel-amber';
    }
    var r = step.reached || {};
    var reached = el('p', 'panel-reached', 'Reached: ' + (r.text || r.kind || ''));
    reached.id = 'panel-reached';
    panel.appendChild(reached);
    if (r.sample) {
      var sample = el('p', 'panel-sample');
      sample.appendChild(document.createTextNode('Sample: '));
      sample.appendChild(el('code', null, r.sample));
      panel.appendChild(sample);
    }

    if (step.contracts && step.contracts.length) {
      var cs = section(panel, 'Claims and contract');
      var ul = el('ul');
      ul.id = 'panel-contracts';
      step.contracts.forEach(function (c) {
        var li = el('li', 'contract contract-' + c.kind);
        li.appendChild(el('span', 'contract-kind', c.kind));
        li.appendChild(document.createTextNode(' '));
        li.appendChild(el('span', 'contract-text', c.text));
        li.appendChild(document.createTextNode(' '));
        li.appendChild(el('span', 'label label-' + (c.label || '').replace(/[^a-z]+/g, '-'), c.label));
        if (c.backing) {
          li.appendChild(document.createTextNode(' '));
          li.appendChild(backingNode(c.backing));
        }
        ul.appendChild(li);
      });
      cs.appendChild(ul);
    }

    if (step.exits) {
      var es = section(panel, 'Exits on this step\'s path');
      if (!step.exits.complete) {
        es.appendChild(el('p', 'incomplete', 'Inventory incomplete: ' + step.exits.incomplete.join('; ')));
      }
      var table = el('table');
      table.id = 'panel-exits';
      var head = el('tr');
      ['Exit', 'Guard', 'Branch', 'In', 'Test evidence'].forEach(function (h) {
        head.appendChild(el('th', null, h));
      });
      table.appendChild(head);
      step.exits.list.forEach(function (x) {
        var tr = el('tr', 'exit');
        tr.setAttribute('data-exit', x.id);
        tr.appendChild(el('td', 'exit-kind', x.kind + (x.type ? ' ' + x.type : '')));
        var guard = el('td', 'exit-guard');
        guard.appendChild(el('code', null, x.guard === null ? 'always' : x.guard));
        if (x.messages && x.messages.length) {
          guard.appendChild(el('div', 'exit-message', x.messages.join(' | ')));
        }
        tr.appendChild(guard);
        tr.appendChild(el('td', 'exit-branch',
            x.pathNotExpanded ? 'path not expanded' : x.branch.join(' && ')));
        var where = el('td', 'exit-symbol');
        where.appendChild(link(x.url, x.symbol));
        tr.appendChild(where);
        var ev = evidenceFor(flow.id, step.id, x.id);
        var evCell = el('td', 'exit-evidence');
        if (!ev) {
          evCell.textContent = window.MAP_INDEXES ? 'not indexed' : 'indexes not loaded';
        } else if (ev.status === 'named') {
          evCell.appendChild(el('span', 'evidence-named', 'named by (text match)'));
          ev.tests.forEach(function (t) {
            evCell.appendChild(el('br'));
            evCell.appendChild(link(t.url, t.test));
          });
        } else if (ev.status === 'none') {
          evCell.appendChild(el('span', 'evidence-none', 'no test names this'));
        } else {
          evCell.appendChild(el('span', 'evidence-undecided', 'undecided: no fixed text to match'));
        }
        tr.appendChild(evCell);
        table.appendChild(tr);
      });
      es.appendChild(table);
    }

    var sk = section(panel, 'Skeleton');
    var pre = el('pre', 'skeleton', step.skeleton);
    pre.id = 'panel-skeleton';
    sk.appendChild(pre);

    var sn = section(panel, 'Code');
    if (step.anchor) {
      var src = el('p', 'source');
      src.appendChild(document.createTextNode(step.anchor.root === 'server' ? 'at_server at the pinned SHA: ' : 'This checkout: '));
      var a = link(step.anchor.url, step.anchor.path + ' ' + step.anchor.symbol);
      a.id = 'panel-source';
      src.appendChild(a);
      sn.appendChild(src);
    }
    if (step.snippet) {
      var code = el('pre', 'snippet', step.snippet.text);
      code.id = 'panel-snippet';
      if (step.snippet.cut) sn.appendChild(el('p', 'cut', 'Cut to a window around the anchored statement.'));
      sn.appendChild(code);
    }

    var ix = window.MAP_INDEXES;
    var stepIx = ix && ix.flows && ix.flows[flow.id] && ix.flows[flow.id].steps[step.id];
    if (stepIx || (step.links && step.links.length)) {
      var more = section(panel, 'Further');
      var list = el('ul');
      (step.links || []).forEach(function (l) {
        var li = el('li');
        li.appendChild(link(repoHref(l.href), l.title));
        list.appendChild(li);
      });
      if (stepIx) {
        stepIx.features.forEach(function (f) {
          var li = el('li');
          li.appendChild(link(repoHref(f), 'Feature ' + f));
          list.appendChild(li);
        });
        stepIx.examples.forEach(function (f) {
          var li = el('li');
          li.appendChild(link(repoHref(f), 'Example ' + f));
          list.appendChild(li);
        });
        stepIx.mentionedBy.forEach(function (t) {
          var li = el('li');
          li.appendChild(link(t.url, 'Test ' + t.path));
          list.appendChild(li);
        });
      }
      more.appendChild(list);
    }
  }

  function showFlow(flowId, stepId) {
    var flow = window.MAP_FLOWS[flowId];
    if (state.flow !== flowId) {
      document.getElementById('flow-title').textContent = flow.title;
      document.getElementById('flow-summary').textContent = flow.summary;
      renderDiagram(flow);
      state.flow = flowId;
    }
    var step = flow.steps.filter(function (s) { return s.id === stepId; })[0] || null;
    state.step = step ? step.id : null;
    Array.prototype.forEach.call(document.querySelectorAll('g.step'), function (g) {
      g.classList.toggle('selected', g.getAttribute('data-step') === state.step);
    });
    renderPanel(flow, step);
    document.body.setAttribute('data-ready', flowId + (step ? '.' + step.id : ''));
  }

  function route() {
    var h = parseHash();
    var flowId = h.flow || (MAP.flows[0] && MAP.flows[0].id);
    if (!flowId || !/^[a-z][a-z0-9-]*$/.test(flowId) ||
        !MAP.flows.some(function (f) { return f.id === flowId; })) {
      document.getElementById('panel').textContent = 'No flow "' + (flowId || '') + '".';
      return;
    }
    loadIndexes(function () {
      if (window.MAP_FLOWS[flowId]) {
        showFlow(flowId, h.step);
        return;
      }
      loadScript('data/flows/' + flowId + '.js', function (ok) {
        if (!ok || !window.MAP_FLOWS[flowId]) {
          document.getElementById('panel').textContent = 'Could not load flow ' + flowId + '.';
          return;
        }
        showFlow(flowId, h.step);
      });
    });
  }

  if (!MAP) {
    document.getElementById('panel').textContent = 'data/core.js did not load.';
    return;
  }
  renderLenses();
  window.addEventListener('hashchange', route);
  route();
})();
