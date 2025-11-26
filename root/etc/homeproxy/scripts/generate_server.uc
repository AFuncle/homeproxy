#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023 ImmortalWrt.org
 */

'use strict';

import { writefile } from 'fs';
import { cursor } from 'uci';

import {
	isEmpty, strToBool, strToInt,
	removeBlankAttrs, HP_DIR, RUN_DIR
} from 'homeproxy';

/* UCI config start */
const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

const uciserver = 'server';

const log_level = uci.get(uciconfig, uciserver, 'log_level') || 'warn';

/* Log level mapping */
function get_xray_loglevel(level) {
	const map = {
		'trace': 'debug',
		'debug': 'debug',
		'info': 'info',
		'warn': 'warning',
		'error': 'error',
		'fatal': 'error',
		'panic': 'none'
	};
	return map[level] || 'warning';
}
/* UCI config end */

const config = {
	log: {
		loglevel: get_xray_loglevel(log_level),
		access: RUN_DIR + '/xray-s.log',
		error: RUN_DIR + '/xray-s.log'
	},
	inbounds: [],
	outbounds: [
		{
			tag: 'direct',
			protocol: 'freedom'
		},
		{
			tag: 'block',
			protocol: 'blackhole'
		}
	],
	routing: {
		rules: []
	}
};

uci.foreach(uciconfig, uciserver, (cfg) => {
	if (cfg.enabled !== '1')
		return;

	let inbound = {
		tag: 'cfg-' + cfg['.name'] + '-in',
		protocol: cfg.type,
		listen: cfg.address || '::',
		port: strToInt(cfg.port),
		settings: {},
		streamSettings: {}
	};

	/* Protocol specific settings */
	switch (cfg.type) {
	case 'vless':
		inbound.settings = {
			clients: [{
				id: cfg.uuid,
				flow: cfg.vless_flow || ''
			}],
			decryption: 'none'
		};
		break;

	case 'vmess':
		inbound.settings = {
			clients: [{
				id: cfg.uuid,
				alterId: strToInt(cfg.vmess_alterid) || 0
			}]
		};
		break;

	case 'trojan':
		inbound.settings = {
			clients: [{
				password: cfg.password
			}]
		};
		break;

	case 'shadowsocks':
		inbound.settings = {
			method: cfg.shadowsocks_encrypt_method,
			password: cfg.password,
			network: cfg.network || 'tcp,udp'
		};
		break;

	case 'socks':
		inbound.settings = {
			auth: (cfg.username && cfg.password) ? 'password' : 'noauth',
			accounts: (cfg.username && cfg.password) ? [{
				user: cfg.username,
				pass: cfg.password
			}] : null,
			udp: true
		};
		break;

	case 'http':
		inbound.settings = {
			accounts: (cfg.username && cfg.password) ? [{
				user: cfg.username,
				pass: cfg.password
			}] : null,
			allowTransparent: false
		};
		break;

	default:
		return;
	}

	/* Transport settings */
	let network = 'tcp';
	if (!isEmpty(cfg.transport)) {
		switch (cfg.transport) {
		case 'ws':
			network = 'ws';
			inbound.streamSettings.wsSettings = {
				path: cfg.ws_path || '/',
				headers: cfg.ws_host ? { Host: cfg.ws_host } : null
			};
			break;

		case 'grpc':
			network = 'grpc';
			inbound.streamSettings.grpcSettings = {
				serviceName: cfg.grpc_servicename || ''
			};
			break;

		case 'http':
			network = 'h2';
			inbound.streamSettings.httpSettings = {
				host: cfg.http_host ? (type(cfg.http_host) === 'array' ? cfg.http_host : [cfg.http_host]) : null,
				path: cfg.http_path || '/'
			};
			break;

		case 'httpupgrade':
			network = 'httpupgrade';
			inbound.streamSettings.httpupgradeSettings = {
				path: cfg.http_path || '/',
				host: cfg.httpupgrade_host
			};
			break;

		case 'quic':
			network = 'quic';
			inbound.streamSettings.quicSettings = {
				security: cfg.quic_security || 'none',
				key: cfg.quic_key,
				header: {
					type: cfg.quic_header_type || 'none'
				}
			};
			break;

		case 'xhttp':
			network = 'xhttp';
			inbound.streamSettings.xhttpSettings = {
				path: cfg.xhttp_path || '/',
				host: cfg.xhttp_host,
				mode: cfg.xhttp_mode || 'auto'
			};
			break;
		}
	}
	inbound.streamSettings.network = network;

	/* TLS settings */
	if (cfg.tls === '1') {
		if (cfg.tls_reality === '1') {
			inbound.streamSettings.security = 'reality';
			inbound.streamSettings.realitySettings = {
				show: false,
				dest: cfg.tls_reality_server_addr + ':' + (cfg.tls_reality_server_port || '443'),
				xver: 0,
				serverNames: cfg.tls_sni ? [cfg.tls_sni] : [],
				privateKey: cfg.tls_reality_private_key,
				shortIds: cfg.tls_reality_short_id ? [cfg.tls_reality_short_id] : ['']
			};
		} else {
			inbound.streamSettings.security = 'tls';
			inbound.streamSettings.tlsSettings = {
				serverName: cfg.tls_sni,
				alpn: cfg.tls_alpn,
				certificates: [{
					certificateFile: cfg.tls_cert_path,
					keyFile: cfg.tls_key_path
				}]
			};
		}
	} else {
		inbound.streamSettings.security = 'none';
	}

	/* Sniffing */
	inbound.sniffing = {
		enabled: true,
		destOverride: ['http', 'tls', 'quic']
	};

	push(config.inbounds, inbound);
});

if (length(config.inbounds) === 0)
	exit(1);

system('mkdir -p ' + RUN_DIR);
writefile(RUN_DIR + '/xray-s.json', sprintf('%.J\n', removeBlankAttrs(config)));
