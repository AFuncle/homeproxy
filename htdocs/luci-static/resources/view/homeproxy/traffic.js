/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2026 HomeProxy contributors
 */

'use strict';
'require dom';
'require poll';
'require rpc';
'require uci';
'require view';

const callTrafficStats = rpc.declare({
	object: 'luci.homeproxy',
	method: 'traffic_stats',
	expect: { '': {} }
});

const css = `
.hp-traffic-head { display:flex; align-items:flex-start; justify-content:space-between; gap:1rem; margin-bottom:1rem; }
.hp-traffic-head h2 { margin:0 0 .35rem; }
.hp-traffic-muted { color:var(--text-color-medium, #667085); }
.hp-traffic-badge { border-radius:999px; padding:.3rem .7rem; font-size:.82rem; font-weight:600; white-space:nowrap; }
.hp-traffic-badge.on { color:#067647; background:#ecfdf3; }
.hp-traffic-badge.off { color:#b54708; background:#fffaeb; }
.hp-traffic-alert { border-left:4px solid #f79009; background:#fffaeb; padding:.8rem 1rem; margin-bottom:1rem; border-radius:4px; }
.hp-traffic-alert a { font-weight:600; }
.hp-traffic-grid { display:grid; grid-template-columns:repeat(4, minmax(0, 1fr)); gap:.8rem; margin-bottom:1rem; }
.hp-traffic-card, .hp-traffic-panel { background:var(--background-color-high, #fff); border:1px solid var(--border-color-medium, #d0d5dd); border-radius:8px; box-shadow:0 1px 2px rgba(16,24,40,.04); }
.hp-traffic-card { padding:1rem; min-height:5.4rem; }
.hp-traffic-card .label { color:var(--text-color-medium, #667085); font-size:.85rem; margin-bottom:.4rem; }
.hp-traffic-card .value { font-size:1.5rem; font-weight:700; line-height:1.15; font-variant-numeric:tabular-nums; }
.hp-traffic-card .sub { color:var(--text-color-medium, #667085); font-size:.78rem; margin-top:.35rem; }
.hp-traffic-panels { display:grid; grid-template-columns:minmax(0, 1.55fr) minmax(20rem, 1fr); gap:1rem; margin-bottom:1rem; }
.hp-traffic-panel { padding:1rem; min-width:0; }
.hp-traffic-panel h3 { margin:0 0 .25rem; }
.hp-traffic-panel .panel-note { margin:0 0 .8rem; font-size:.8rem; color:var(--text-color-medium, #667085); }
.hp-traffic-canvas { width:100%; height:280px; display:block; }
.hp-traffic-table-wrap { overflow:auto; }
.hp-traffic-table { width:100%; border-collapse:collapse; }
.hp-traffic-table th, .hp-traffic-table td { padding:.65rem .55rem; border-bottom:1px solid var(--border-color-low, #eaecf0); text-align:right; white-space:nowrap; }
.hp-traffic-table th { color:var(--text-color-medium, #667085); font-size:.78rem; }
.hp-traffic-table th:first-child, .hp-traffic-table td:first-child { text-align:left; }
.hp-traffic-table tbody tr:last-child td { border-bottom:0; }
.hp-traffic-provider { min-width:10rem; }
.hp-traffic-provider small { display:block; color:var(--text-color-medium, #667085); max-width:26rem; overflow:hidden; text-overflow:ellipsis; }
.hp-traffic-share { display:inline-block; min-width:4.2rem; }
.hp-traffic-error { color:#b42318; padding:1rem 0; }
@media (max-width:900px) {
	.hp-traffic-grid { grid-template-columns:repeat(2, minmax(0, 1fr)); }
	.hp-traffic-panels { grid-template-columns:1fr; }
}
@media (max-width:520px) {
	.hp-traffic-head { flex-direction:column; }
	.hp-traffic-grid { grid-template-columns:1fr; }
}
`;

function number(v) {
	v = Number(v);
	return Number.isFinite(v) && v > 0 ? v : 0;
}

function formatBytes(bytes) {
	const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
	let value = number(bytes), unit = 0;
	while (value >= 1024 && unit < units.length - 1) {
		value /= 1024;
		unit++;
	}
	return String.format('%s %s', value >= 100 || unit === 0 ? value.toFixed(0) : value.toFixed(1), units[unit]);
}

function formatRate(bytes) {
	return formatBytes(bytes) + '/s';
}

function aggregate(items, filter) {
	let result = { uplink: 0, downlink: 0 };
	Object.keys(items || {}).forEach((tag) => {
		if (!filter || filter(tag)) {
			result.uplink += number(items[tag]?.uplink);
			result.downlink += number(items[tag]?.downlink);
		}
	});
	return result;
}

function resizeCanvas(canvas, height) {
	const ratio = Math.max(1, window.devicePixelRatio || 1);
	const width = Math.max(320, canvas.getBoundingClientRect().width || 640);
	canvas.width = Math.floor(width * ratio);
	canvas.height = Math.floor(height * ratio);
	canvas.style.height = height + 'px';
	const ctx = canvas.getContext('2d');
	ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
	return { ctx: ctx, width: width, height: height };
}

function canvasColor(name, fallback) {
	const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
	return value || fallback;
}

function drawRealtime(canvas, history) {
	const size = resizeCanvas(canvas, 280), ctx = size.ctx;
	const width = size.width, height = size.height;
	const pad = { left: 58, right: 16, top: 18, bottom: 28 };
	const plotW = width - pad.left - pad.right, plotH = height - pad.top - pad.bottom;
	const max = Math.max(1024, ...history.map((p) => Math.max(p.uplink, p.downlink))) * 1.12;
	const grid = canvasColor('--border-color-low', '#e4e7ec');
	const text = canvasColor('--text-color-medium', '#667085');

	ctx.clearRect(0, 0, width, height);
	ctx.font = '11px sans-serif';
	ctx.fillStyle = text;
	ctx.strokeStyle = grid;
	ctx.lineWidth = 1;
	for (let i = 0; i <= 4; i++) {
		const y = pad.top + plotH * i / 4;
		ctx.beginPath(); ctx.moveTo(pad.left, y); ctx.lineTo(width - pad.right, y); ctx.stroke();
		ctx.textAlign = 'right';
		ctx.fillText(formatRate(max * (4 - i) / 4), pad.left - 7, y + 4);
	}

	const draw = (key, color) => {
		if (!history.length) return;
		ctx.beginPath();
		history.forEach((point, index) => {
			const x = pad.left + (history.length === 1 ? plotW : plotW * index / (history.length - 1));
			const y = pad.top + plotH - (number(point[key]) / max * plotH);
			if (index === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
		});
		ctx.strokeStyle = color; ctx.lineWidth = 2; ctx.lineJoin = 'round'; ctx.stroke();
	};
	draw('downlink', '#2e90fa');
	draw('uplink', '#12b76a');

	ctx.textAlign = 'left'; ctx.fillStyle = '#2e90fa'; ctx.fillRect(pad.left, height - 12, 16, 3);
	ctx.fillStyle = text; ctx.fillText(_('Download'), pad.left + 22, height - 8);
	ctx.fillStyle = '#12b76a'; ctx.fillRect(pad.left + 100, height - 12, 16, 3);
	ctx.fillStyle = text; ctx.fillText(_('Upload'), pad.left + 122, height - 8);
}

function drawProviders(canvas, providers) {
	const rows = providers.slice(0, 10);
	const size = resizeCanvas(canvas, 280), ctx = size.ctx;
	const width = size.width, height = size.height;
	const left = Math.min(126, width * .34), right = 12, top = 8;
	const rowH = rows.length ? Math.min(26, (height - top) / rows.length) : 26;
	const max = Math.max(1, ...rows.map((row) => row.total));
	const text = canvasColor('--text-color-medium', '#667085');
	ctx.clearRect(0, 0, width, height);
	ctx.font = '11px sans-serif';
	if (!rows.length) {
		ctx.fillStyle = text; ctx.textAlign = 'center';
		ctx.fillText(_('No classified traffic yet.'), width / 2, height / 2);
		return;
	}
	rows.forEach((row, index) => {
		const y = top + index * rowH;
		const available = width - left - right;
		const upW = available * row.uplink / max;
		const downW = available * row.downlink / max;
		ctx.fillStyle = text; ctx.textAlign = 'right';
		ctx.fillText(row.label.length > 18 ? row.label.slice(0, 17) + '…' : row.label, left - 7, y + 14);
		ctx.fillStyle = '#12b76a'; ctx.fillRect(left, y + 3, upW, 14);
		ctx.fillStyle = '#2e90fa'; ctx.fillRect(left + upW, y + 3, downW, 14);
	});
}

function trafficRow(name, traffic, total, detail) {
	const sum = traffic.uplink + traffic.downlink;
	const share = total > 0 ? sum * 100 / total : 0;
	return E('tr', {}, [
		E('td', { 'class': 'hp-traffic-provider' }, [ name, detail ? E('small', { 'title': detail }, detail) : '' ]),
		E('td', {}, formatBytes(traffic.uplink)),
		E('td', {}, formatBytes(traffic.downlink)),
		E('td', {}, formatBytes(sum)),
		E('td', {}, E('span', { 'class': 'hp-traffic-share' }, share.toFixed(1) + '%'))
	]);
}

return view.extend({
	load() {
		return uci.load('homeproxy');
	},

	render() {
		const deepEnabled = uci.get('homeproxy', 'config', 'traffic_analysis') === '1';
		const history = [];
		let previous = null;

		const downloadRate = E('div', { 'class': 'value' }, '--');
		const uploadRate = E('div', { 'class': 'value' }, '--');
		const downloadTotal = E('div', { 'class': 'value' }, '--');
		const uploadTotal = E('div', { 'class': 'value' }, '--');
		const updated = E('span', {}, _('Waiting for Xray metrics...'));
		const error = E('div', { 'class': 'hp-traffic-error', 'style': 'display:none' });
		const realtimeCanvas = E('canvas', { 'class': 'hp-traffic-canvas' });
		const providerCanvas = E('canvas', { 'class': 'hp-traffic-canvas' });
		const providerBody = E('tbody');
		const outboundBody = E('tbody');

		const table = (body) => E('div', { 'class': 'hp-traffic-table-wrap' }, E('table', { 'class': 'hp-traffic-table' }, [
			E('thead', {}, E('tr', {}, [
				E('th', {}, _('Name')),
				E('th', {}, _('Upload')),
				E('th', {}, _('Download')),
				E('th', {}, _('Total')),
				E('th', {}, _('Share'))
			])),
			body
		]));

		poll.add(() => L.resolveDefault(callTrafficStats(), { result: false, error: _('Xray metrics are unavailable.') }).then((response) => {
			if (!response.result) {
				error.style.display = '';
				dom.content(error, response.error || _('Xray metrics are unavailable.'));
				return;
			}
			error.style.display = 'none';

			const stats = response.stats || {};
			const ingress = aggregate(stats.inbound, (tag) => tag !== 'dns-in' && tag !== 'traffic-stats-in');
			const now = Date.now();
			let rates = { uplink: 0, downlink: 0 };
			if (previous) {
				const seconds = Math.max(.25, (now - previous.time) / 1000);
				rates.uplink = ingress.uplink >= previous.uplink ? (ingress.uplink - previous.uplink) / seconds : 0;
				rates.downlink = ingress.downlink >= previous.downlink ? (ingress.downlink - previous.downlink) / seconds : 0;
			}
			previous = { uplink: ingress.uplink, downlink: ingress.downlink, time: now };
			history.push(rates);
			if (history.length > 60) history.shift();

			dom.content(downloadRate, formatRate(rates.downlink));
			dom.content(uploadRate, formatRate(rates.uplink));
			dom.content(downloadTotal, formatBytes(ingress.downlink));
			dom.content(uploadTotal, formatBytes(ingress.uplink));
			dom.content(updated, _('Updated at %s').format(new Date(now).toLocaleTimeString()));
			drawRealtime(realtimeCanvas, history);

			const total = ingress.uplink + ingress.downlink;
			const providers = (response.categories || []).map((category) => {
				const traffic = stats.user?.['hp-traffic-' + category.id] || {};
				return {
					label: category.label || category.id,
					detail: (category.domains || []).map((domain) => domain.replace(/^domain:/, '')).join(', '),
					uplink: number(traffic.uplink),
					downlink: number(traffic.downlink),
					total: number(traffic.uplink) + number(traffic.downlink)
				};
			}).sort((a, b) => b.total - a.total);
			drawProviders(providerCanvas, providers);
			dom.content(providerBody, providers.map((row) => trafficRow(row.label, row, total, row.detail)));

			const outbounds = Object.keys(stats.outbound || {}).filter((tag) =>
				!tag.startsWith('hp-traffic-') && tag !== 'dns-out'
			).map((tag) => {
				const traffic = stats.outbound[tag] || {};
				return { tag: tag, uplink: number(traffic.uplink), downlink: number(traffic.downlink) };
			}).sort((a, b) => (b.uplink + b.downlink) - (a.uplink + a.downlink));
			const outboundTotal = outbounds.reduce((sum, row) => sum + row.uplink + row.downlink, 0);
			dom.content(outboundBody, outbounds.map((row) => trafficRow(row.tag, row, outboundTotal)));
		}));

		return E('div', {}, [
			E('style', [ css ]),
			E('div', { 'class': 'hp-traffic-head' }, [
				E('div', {}, [
					E('h2', {}, _('Traffic Analysis')),
					E('div', { 'class': 'hp-traffic-muted' }, [ _('Real-time Xray traffic with exact provider attribution. '), updated ])
				]),
				E('span', { 'class': 'hp-traffic-badge ' + (deepEnabled ? 'on' : 'off') }, deepEnabled ? _('Deep analysis enabled') : _('Basic statistics only'))
			]),
			deepEnabled ? '' : E('div', { 'class': 'hp-traffic-alert' }, [
				_('Enable deep traffic analysis in Client Settings to classify Tencent, Baidu and other provider traffic by exact byte count. '),
				E('a', { 'href': L.url('admin/services/homeproxy/client') }, _('Open Client Settings'))
			]),
			error,
			E('div', { 'class': 'hp-traffic-grid' }, [
				E('div', { 'class': 'hp-traffic-card' }, [ E('div', { 'class': 'label' }, _('Real-time download')), downloadRate, E('div', { 'class': 'sub' }, _('Current sampling rate')) ]),
				E('div', { 'class': 'hp-traffic-card' }, [ E('div', { 'class': 'label' }, _('Real-time upload')), uploadRate, E('div', { 'class': 'sub' }, _('Current sampling rate')) ]),
				E('div', { 'class': 'hp-traffic-card' }, [ E('div', { 'class': 'label' }, _('Downloaded since start')), downloadTotal, E('div', { 'class': 'sub' }, _('Counters reset when Xray restarts')) ]),
				E('div', { 'class': 'hp-traffic-card' }, [ E('div', { 'class': 'label' }, _('Uploaded since start')), uploadTotal, E('div', { 'class': 'sub' }, _('Counters reset when Xray restarts')) ])
			]),
			E('div', { 'class': 'hp-traffic-panels' }, [
				E('div', { 'class': 'hp-traffic-panel' }, [ E('h3', {}, _('Real-time traffic')), E('p', { 'class': 'panel-note' }, _('Last 60 samples; blue is download and green is upload.')), realtimeCanvas ]),
				E('div', { 'class': 'hp-traffic-panel' }, [ E('h3', {}, _('Provider traffic ranking')), E('p', { 'class': 'panel-note' }, _('Top providers by total traffic.')), providerCanvas ])
			]),
			E('div', { 'class': 'hp-traffic-panel', 'style': 'margin-bottom:1rem' }, [
				E('h3', {}, _('Provider and domain-group traffic')),
				E('p', { 'class': 'panel-note' }, _('Hover a provider name to see the domains included in that group. Unclassified IP-only or encrypted traffic remains in the total but is not assigned to a provider.')),
				table(providerBody)
			]),
			E('div', { 'class': 'hp-traffic-panel' }, [
				E('h3', {}, _('Outbound traffic')),
				E('p', { 'class': 'panel-note' }, _('Traffic counters grouped by the final Xray outbound.')),
				table(outboundBody)
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
