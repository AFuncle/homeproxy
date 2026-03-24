#!/usr/bin/ucode
/*
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Copyright (C) 2023-2025 ImmortalWrt.org
 */

'use strict';

import { readfile, writefile } from 'fs';
import { connect } from 'ubus';
import { cursor } from 'uci';

import {
	isEmpty, strToBool, strToInt,
	removeBlankAttrs, HP_DIR, RUN_DIR
} from 'homeproxy';

const ubus = connect();

/* UCI config start */
const uci = cursor();

const uciconfig = 'homeproxy';
uci.load(uciconfig);

const uciinfra = 'infra',
      ucimain = 'config',
      ucicontrol = 'control';

const ucidnssetting = 'dns',
      ucidnsserver = 'dns_server',
      ucidnsrule = 'dns_rule';

const uciroutingsetting = 'routing',
      uciroutingnode = 'routing_node',
      uciroutingrule = 'routing_rule';

const ucinode = 'node';

const routing_mode = uci.get(uciconfig, ucimain, 'routing_mode') || 'bypass_mainland_china';

let wan_dns = ubus.call('network.interface', 'status', {'interface': 'wan'})?.['dns-server']?.[0];
if (!wan_dns)
	wan_dns = (routing_mode in ['proxy_mainland_china', 'global']) ? '8.8.8.8' : '223.5.5.5';

const dns_port = uci.get(uciconfig, uciinfra, 'dns_port') || '5333';
const ipv6_support = uci.get(uciconfig, ucimain, 'ipv6_support') || '0';

let main_node, main_udp_node, dedicated_udp_node, default_outbound,
    dns_server, china_dns_server, direct_domain_list, proxy_domain_list,
    sniff_override;

if (routing_mode !== 'custom') {
	main_node = uci.get(uciconfig, ucimain, 'main_node') || 'nil';
	main_udp_node = uci.get(uciconfig, ucimain, 'main_udp_node') || 'nil';
	dedicated_udp_node = !isEmpty(main_udp_node) && !(main_udp_node in ['same', main_node]);

	dns_server = uci.get(uciconfig, ucimain, 'dns_server');
	if (isEmpty(dns_server) || dns_server === 'wan')
		dns_server = wan_dns;

	if (routing_mode === 'bypass_mainland_china') {
		china_dns_server = uci.get(uciconfig, ucimain, 'china_dns_server');
		if (isEmpty(china_dns_server) || type(china_dns_server) !== 'string' || china_dns_server === 'wan')
			china_dns_server = wan_dns;
	}

	direct_domain_list = trim(readfile(HP_DIR + '/resources/direct_list.txt'));
	if (direct_domain_list)
		direct_domain_list = split(direct_domain_list, /[\r\n]/);

	proxy_domain_list = trim(readfile(HP_DIR + '/resources/proxy_list.txt'));
	if (proxy_domain_list)
		proxy_domain_list = split(proxy_domain_list, /[\r\n]/);

	sniff_override = uci.get(uciconfig, uciinfra, 'sniff_override') || '1';
} else {
	default_outbound = uci.get(uciconfig, uciroutingsetting, 'default_outbound') || 'nil';
	sniff_override = uci.get(uciconfig, uciroutingsetting, 'sniff_override');
}

const proxy_mode = uci.get(uciconfig, ucimain, 'proxy_mode') || 'redirect_tproxy';
const mixed_port = uci.get(uciconfig, uciinfra, 'mixed_port') || '5330';

let self_mark, redirect_port, tproxy_port;

if (match(proxy_mode, /redirect/)) {
	self_mark = uci.get(uciconfig, 'infra', 'self_mark') || '100';
	redirect_port = uci.get(uciconfig, 'infra', 'redirect_port') || '5331';
}
if (match(proxy_mode, /tproxy/)) {
	if (main_udp_node !== 'nil' || routing_mode === 'custom' || proxy_mode === 'tproxy')
		tproxy_port = uci.get(uciconfig, 'infra', 'tproxy_port') || '5332';
}

const log_level = uci.get(uciconfig, ucimain, 'log_level') || 'warn';

/* UCI config end */

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

/* Generate Xray outbound from node config */
function generate_outbound(node) {
	if (type(node) !== 'object' || isEmpty(node))
		return null;

	let outbound = {
		tag: 'cfg-' + node['.name'] + '-out',
		protocol: node.type,
		settings: {},
		streamSettings: {}
	};

	/* Server settings based on protocol */
	switch (node.type) {
	case 'vless':
		outbound.settings = {
			vnext: [{
				address: node.address,
				port: strToInt(node.port),
				users: [{
					id: node.uuid,
					encryption: 'none',
					flow: node.vless_flow || ''
				}]
			}]
		};
		break;

	case 'vmess':
		outbound.settings = {
			vnext: [{
				address: node.address,
				port: strToInt(node.port),
				users: [{
					id: node.uuid,
					alterId: strToInt(node.vmess_alterid) || 0,
					security: node.vmess_encrypt || 'auto'
				}]
			}]
		};
		break;

	case 'trojan':
		outbound.settings = {
			servers: [{
				address: node.address,
				port: strToInt(node.port),
				password: node.password
			}]
		};
		break;

	case 'shadowsocks':
		outbound.settings = {
			servers: [{
				address: node.address,
				port: strToInt(node.port),
				method: node.shadowsocks_encrypt_method,
				password: node.password
			}]
		};
		break;

	case 'socks':
		outbound.settings = {
			servers: [{
				address: node.address,
				port: strToInt(node.port),
				users: (node.username && node.password) ? [{
					user: node.username,
					pass: node.password
				}] : null
			}]
		};
		break;

	case 'http':
		outbound.settings = {
			servers: [{
				address: node.address,
				port: strToInt(node.port),
				users: (node.username && node.password) ? [{
					user: node.username,
					pass: node.password
				}] : null
			}]
		};
		break;

	default:
		return null;
	}

	/* Stream settings */
	let network = 'tcp';
	if (!isEmpty(node.transport)) {
		switch (node.transport) {
		case 'ws':
			network = 'ws';
			outbound.streamSettings.wsSettings = {
				path: node.ws_path || '/',
				headers: node.ws_host ? { Host: node.ws_host } : null
			};
			break;

		case 'grpc':
			network = 'grpc';
			outbound.streamSettings.grpcSettings = {
				serviceName: node.grpc_servicename || '',
				multiMode: strToBool(node.grpc_multi_mode),
				idle_timeout: strToInt(node.grpc_idle_timeout),
				health_check_timeout: strToInt(node.grpc_health_check_timeout),
				permit_without_stream: strToBool(node.grpc_permit_without_stream)
			};
			break;

		case 'http':
			network = 'h2';
			outbound.streamSettings.httpSettings = {
				host: node.http_host ? (type(node.http_host) === 'array' ? node.http_host : [node.http_host]) : null,
				path: node.http_path || '/',
				method: node.http_method
			};
			break;

		case 'httpupgrade':
			network = 'httpupgrade';
			outbound.streamSettings.httpupgradeSettings = {
				path: node.http_path || '/',
				host: node.httpupgrade_host
			};
			break;

		case 'quic':
			network = 'quic';
			outbound.streamSettings.quicSettings = {
				security: node.quic_security || 'none',
				key: node.quic_key,
				header: {
					type: node.quic_header_type || 'none'
				}
			};
			break;

		case 'xhttp':
			network = 'xhttp';
			outbound.streamSettings.xhttpSettings = {
				path: node.xhttp_path || '/',
				host: node.xhttp_host,
				mode: node.xhttp_mode || 'auto',
				extra: (function(str) {
					if (!str) return null;
					try { return json(str); }
					catch(e) { return null; }
				})(node.xhttp_extra)
			};
			break;
		}
	}
	outbound.streamSettings.network = network;

	/* Shadowsocks obfs plugin: translate obfs-local/simple-obfs to xray TCP header obfuscation */
	if (node.type === 'shadowsocks' && !isEmpty(node.shadowsocks_plugin) && !isEmpty(node.shadowsocks_plugin_opts)) {
		let plugin_opts = {};
		for (let part in split(node.shadowsocks_plugin_opts, ';')) {
			let kv = split(part, '=', 2);
			if (length(kv) === 2)
				plugin_opts[kv[0]] = kv[1];
		}

		if (plugin_opts.obfs === 'http') {
			outbound.streamSettings.network = 'tcp';
			outbound.streamSettings.tcpSettings = {
				header: {
					type: 'http',
					request: {
						version: '1.1',
						method: 'GET',
						path: [plugin_opts.path || '/'],
						headers: {
							'Host': [plugin_opts['obfs-host'] || 'www.bing.com'],
							'User-Agent': ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'],
							'Accept-Encoding': ['gzip, deflate'],
							'Connection': ['keep-alive'],
							'Pragma': 'no-cache'
						}
					}
				}
			};
		}
	}

	/* TLS settings */
	if (node.tls === '1') {
		if (node.tls_reality === '1') {
			outbound.streamSettings.security = 'reality';
			outbound.streamSettings.realitySettings = {
				serverName: node.tls_sni,
				fingerprint: node.tls_utls || 'chrome',
				publicKey: node.tls_reality_public_key,
				shortId: node.tls_reality_short_id,
				spiderX: ''
			};
		} else {
			outbound.streamSettings.security = 'tls';
			outbound.streamSettings.tlsSettings = {
				serverName: node.tls_sni,
				allowInsecure: strToBool(node.tls_insecure),
				alpn: node.tls_alpn,
				fingerprint: node.tls_utls
			};
		}
	} else {
		outbound.streamSettings.security = 'none';
	}

	/* Socket options - always use Xray internal DNS for node domain resolution
	 * to prevent DNS deadlock under transparent proxy */
	outbound.streamSettings.sockopt = {
		domainStrategy: (ipv6_support === '1') ? 'UseIP' : 'UseIPv4'
	};
	if (self_mark)
		outbound.streamSettings.sockopt.mark = strToInt(self_mark);

	/* Mux settings */
	if (node.multiplex === '1') {
		outbound.mux = {
			enabled: true,
			concurrency: strToInt(node.multiplex_max_connections) || 8
		};
	}

	return outbound;
}

function get_outbound(cfg) {
	if (isEmpty(cfg))
		return null;

	switch (cfg) {
	case 'block-out':
		return 'block-out';
	case 'direct-out':
		return 'direct-out';
	default:
		const node = uci.get(uciconfig, cfg, 'node');
		if (isEmpty(node))
			return null;
		return 'cfg-' + node + '-out';
	}
}

/* Xray config */
const config = {
	log: {
		loglevel: get_xray_loglevel(log_level),
		access: (log_level in ['trace', 'debug', 'info']) ? (RUN_DIR + '/xray-c.log') : null,
		error: RUN_DIR + '/xray-c.log'
	},
	dns: {
		servers: [],
		hosts: {}
	},
	inbounds: [],
	outbounds: [],
	routing: {
		domainStrategy: (ipv6_support !== '1') ? 'IPIfNonMatch' : 'AsIs',
		rules: []
	}
};

/* DNS configuration */
if ((main_node && main_node !== 'nil') || (default_outbound && default_outbound !== 'nil')) {
	/* Remote DNS for proxy */
	push(config.dns.servers, {
		address: dns_server,
		port: 53,
		domains: []
	});

	if (routing_mode === 'bypass_mainland_china') {
		/* China DNS */
		push(config.dns.servers, {
			address: china_dns_server,
			port: 53,
			domains: ['geosite:cn'],
			expectIPs: ['geoip:cn']
		});

		/* Proxy domains use remote DNS */
		if (length(proxy_domain_list)) {
			for (let d in proxy_domain_list) {
				if (d && trim(d) !== '')
					push(config.dns.servers[0].domains, 'domain:' + trim(d));
			}
		}
	}

	/* Direct domains use local DNS */
	if (length(direct_domain_list)) {
		let direct_dns = {
			address: wan_dns,
			port: 53,
			domains: []
		};
		for (let d in direct_domain_list) {
			if (d && trim(d) !== '')
				push(direct_dns.domains, 'domain:' + trim(d));
		}
		if (length(direct_dns.domains))
			push(config.dns.servers, direct_dns);
	}

	/* Default fallback */
	push(config.dns.servers, wan_dns);
}

/* Inbounds */
/* DNS inbound */
push(config.inbounds, {
	tag: 'dns-in',
	protocol: 'dokodemo-door',
	listen: '::',
	port: strToInt(dns_port),
	settings: {
		address: '8.8.8.8',
		port: 53,
		network: 'tcp,udp'
	}
});

/* Mixed (SOCKS+HTTP) inbound */
push(config.inbounds, {
	tag: 'mixed-in',
	protocol: 'socks',
	listen: '::',
	port: strToInt(mixed_port),
	settings: {
		auth: 'noauth',
		udp: true
	},
	sniffing: strToBool(sniff_override) ? {
		enabled: true,
		destOverride: ['http', 'tls', 'quic'],
		routeOnly: true
	} : null
});

/* Redirect inbound (TCP) */
if (match(proxy_mode, /redirect/)) {
	push(config.inbounds, {
		tag: 'redirect-in',
		protocol: 'dokodemo-door',
		listen: '::',
		port: strToInt(redirect_port),
		settings: {
			network: 'tcp',
			followRedirect: true
		},
		sniffing: strToBool(sniff_override) ? {
			enabled: true,
			destOverride: ['http', 'tls', 'quic'],
			routeOnly: true
		} : null
	});
}

/* TProxy inbound (UDP) */
if (tproxy_port) {
	push(config.inbounds, {
		tag: 'tproxy-in',
		protocol: 'dokodemo-door',
		listen: '::',
		port: strToInt(tproxy_port),
		settings: {
			network: 'udp',
			followRedirect: true
		},
		sniffing: strToBool(sniff_override) ? {
			enabled: true,
			destOverride: ['http', 'tls', 'quic'],
			routeOnly: true
		} : null,
		streamSettings: {
			sockopt: {
				tproxy: 'tproxy'
			}
		}
	});
}

/* Outbounds */
/* Direct outbound */
push(config.outbounds, {
	tag: 'direct-out',
	protocol: 'freedom',
	settings: {
		domainStrategy: 'UseIP'
	},
	streamSettings: self_mark ? {
		sockopt: {
			mark: strToInt(self_mark)
		}
	} : null
});

/* Block outbound */
push(config.outbounds, {
	tag: 'block-out',
	protocol: 'blackhole',
	settings: {
		response: {
			type: 'none'
		}
	}
});

/* DNS outbound */
push(config.outbounds, {
	tag: 'dns-out',
	protocol: 'dns'
});

/* Main proxy outbounds */
if (main_node && main_node !== 'nil') {
	if (main_node === 'urltest') {
		/* URLTest - use balancer in Xray */
		const main_urltest_nodes = uci.get(uciconfig, ucimain, 'main_urltest_nodes') || [];

		for (let i in main_urltest_nodes) {
			const node_cfg = uci.get_all(uciconfig, i) || {};
			if (!isEmpty(node_cfg)) {
				let out = generate_outbound(node_cfg);
				if (out)
					push(config.outbounds, out);
			}
		}

		/* Add balancer for urltest */
		config.routing.balancers = [{
			tag: 'main-balancer',
			selector: map(main_urltest_nodes, (k) => `cfg-${k}-out`),
			strategy: {
				type: 'leastPing'
			}
		}];

		/* Main-out points to balancer */
		push(config.outbounds, {
			tag: 'main-out',
			protocol: 'loopback',
			settings: {}
		});
	} else {
		const main_node_cfg = uci.get_all(uciconfig, main_node) || {};
		let out = generate_outbound(main_node_cfg);
		if (out) {
			out.tag = 'main-out';
			push(config.outbounds, out);
		}
	}

	/* UDP node */
	if (dedicated_udp_node) {
		if (main_udp_node === 'urltest') {
			const main_udp_urltest_nodes = uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes') || [];

			for (let i in main_udp_urltest_nodes) {
				/* Skip if already added */
				let exists = false;
				for (let o in config.outbounds) {
					if (o.tag === 'cfg-' + i + '-out') {
						exists = true;
						break;
					}
				}
				if (!exists) {
					const node_cfg = uci.get_all(uciconfig, i) || {};
					if (!isEmpty(node_cfg)) {
						let out = generate_outbound(node_cfg);
						if (out)
							push(config.outbounds, out);
					}
				}
			}

			if (!config.routing.balancers)
				config.routing.balancers = [];

			push(config.routing.balancers, {
				tag: 'main-udp-balancer',
				selector: map(main_udp_urltest_nodes, (k) => `cfg-${k}-out`),
				strategy: {
					type: 'leastPing'
				}
			});
		} else {
			const main_udp_node_cfg = uci.get_all(uciconfig, main_udp_node) || {};
			let out = generate_outbound(main_udp_node_cfg);
			if (out) {
				out.tag = 'main-udp-out';
				push(config.outbounds, out);
			}
		}
	}
} else if (default_outbound && default_outbound !== 'nil') {
	/* Custom routing mode */
	let routing_nodes = [];

	uci.foreach(uciconfig, uciroutingnode, (cfg) => {
		if (cfg.enabled !== '1')
			return;

		if (cfg.node === 'urltest') {
			/* URLTest nodes */
			const urltest_nodes = cfg.urltest_nodes || [];
			for (let i in urltest_nodes) {
				let exists = false;
				for (let o in config.outbounds) {
					if (o.tag === 'cfg-' + i + '-out') {
						exists = true;
						break;
					}
				}
				if (!exists) {
					const node_cfg = uci.get_all(uciconfig, i) || {};
					if (!isEmpty(node_cfg)) {
						let out = generate_outbound(node_cfg);
						if (out)
							push(config.outbounds, out);
					}
				}
			}

			if (!config.routing.balancers)
				config.routing.balancers = [];

			push(config.routing.balancers, {
				tag: 'cfg-' + cfg['.name'] + '-balancer',
				selector: map(urltest_nodes, (k) => `cfg-${k}-out`),
				strategy: {
					type: 'leastPing'
				}
			});
		} else {
			const outbound = uci.get_all(uciconfig, cfg.node) || {};
			let out = generate_outbound(outbound);
			if (out)
				push(config.outbounds, out);
			push(routing_nodes, cfg.node);
		}
	});
}

/* Routing rules */
/* DNS hijack */
push(config.routing.rules, {
	type: 'field',
	inboundTag: ['dns-in'],
	outboundTag: 'dns-out'
});

/* Block QUIC for better compatibility */
push(config.routing.rules, {
	type: 'field',
	port: 443,
	network: 'udp',
	outboundTag: 'block-out'
});

if (main_node && main_node !== 'nil') {
	/* Direct domains */
	if (length(direct_domain_list)) {
		let domains = [];
		for (let d in direct_domain_list) {
			if (d && trim(d) !== '')
				push(domains, 'domain:' + trim(d));
		}
		if (length(domains)) {
			push(config.routing.rules, {
				type: 'field',
				domain: domains,
				outboundTag: 'direct-out'
			});
		}
	}

	/* Proxy domains */
	if (length(proxy_domain_list)) {
		let domains = [];
		for (let d in proxy_domain_list) {
			if (d && trim(d) !== '')
				push(domains, 'domain:' + trim(d));
		}
		if (length(domains)) {
			push(config.routing.rules, {
				type: 'field',
				domain: domains,
				outboundTag: 'main-out'
			});
		}
	}

	if (routing_mode === 'bypass_mainland_china') {
		/* China sites direct */
		push(config.routing.rules, {
			type: 'field',
			domain: ['geosite:cn'],
			outboundTag: 'direct-out'
		});

		/* China IPs direct */
		push(config.routing.rules, {
			type: 'field',
			ip: ['geoip:cn', 'geoip:private'],
			outboundTag: 'direct-out'
		});
	} else if (routing_mode === 'gfwlist') {
		/* GFW list proxy */
		push(config.routing.rules, {
			type: 'field',
			domain: ['geosite:gfw', 'geosite:greatfire'],
			outboundTag: 'main-out'
		});

		/* Default direct */
		push(config.routing.rules, {
			type: 'field',
			ip: ['geoip:private'],
			outboundTag: 'direct-out'
		});
	} else if (routing_mode === 'proxy_mainland_china') {
		/* Proxy China only */
		push(config.routing.rules, {
			type: 'field',
			domain: ['geosite:cn'],
			outboundTag: 'main-out'
		});

		push(config.routing.rules, {
			type: 'field',
			ip: ['geoip:cn'],
			outboundTag: 'main-out'
		});

		/* Others direct */
		push(config.routing.rules, {
			type: 'field',
			ip: ['geoip:private'],
			outboundTag: 'direct-out'
		});
	}

	/* UDP routing */
	if (dedicated_udp_node) {
		push(config.routing.rules, {
			type: 'field',
			network: 'udp',
			outboundTag: main_udp_node === 'urltest' ? null : 'main-udp-out',
			balancerTag: main_udp_node === 'urltest' ? 'main-udp-balancer' : null
		});
	}

	/* Default outbound based on routing mode */
	if (routing_mode === 'bypass_mainland_china' || routing_mode === 'global') {
		/* Default to proxy */
		push(config.routing.rules, {
			type: 'field',
			port: '0-65535',
			outboundTag: main_node === 'urltest' ? null : 'main-out',
			balancerTag: main_node === 'urltest' ? 'main-balancer' : null
		});
	} else if (routing_mode === 'gfwlist' || routing_mode === 'proxy_mainland_china') {
		/* Default to direct */
		push(config.routing.rules, {
			type: 'field',
			port: '0-65535',
			outboundTag: 'direct-out'
		});
	}
} else if (default_outbound && default_outbound !== 'nil') {
	/* Custom routing rules */
	uci.foreach(uciconfig, uciroutingrule, (cfg) => {
		if (cfg.enabled !== '1')
			return null;

		let rule = {
			type: 'field'
		};

		if (cfg.protocol)
			rule.protocol = cfg.protocol;
		if (cfg.network)
			rule.network = cfg.network;
		if (cfg.domain)
			rule.domain = cfg.domain;
		if (cfg.domain_suffix)
			rule.domain = [...(rule.domain || []), ...map(cfg.domain_suffix, (d) => 'domain:' + d)];
		if (cfg.domain_keyword)
			rule.domain = [...(rule.domain || []), ...map(cfg.domain_keyword, (d) => 'keyword:' + d)];
		if (cfg.ip_cidr)
			rule.ip = cfg.ip_cidr;
		if (cfg.source_ip_cidr)
			rule.source = cfg.source_ip_cidr;
		if (cfg.port) {
			let ports = [];
			for (let p in cfg.port)
				push(ports, strToInt(p));
			rule.port = join(',', ports);
		}
		if (cfg.source_port) {
			let ports = [];
			for (let p in cfg.source_port)
				push(ports, strToInt(p));
			rule.sourcePort = join(',', ports);
		}
		if (cfg.invert)
			rule.invert = strToBool(cfg.invert);

		let outbound = get_outbound(cfg.outbound);
		if (outbound)
			rule.outboundTag = outbound;

		push(config.routing.rules, rule);
	});

	/* Default rule */
	let default_out = get_outbound(default_outbound);
	if (default_out) {
		push(config.routing.rules, {
			type: 'field',
			port: '0-65535',
			outboundTag: default_out
		});
	}
}

/* Private IPs always direct */
if (routing_mode !== 'global') {
	/* Insert at beginning for priority */
	unshift(config.routing.rules, {
		type: 'field',
		ip: ['geoip:private'],
		outboundTag: 'direct-out'
	});
}

/* Resolve node server domains via direct domestic DNS to avoid DNS deadlock.
 * Without this, node domains (not in geosite:cn) would be resolved through
 * the proxy DNS, but the proxy itself needs those domains resolved first,
 * causing a circular dependency that prevents the proxy from starting. */
if (config.dns && length(config.dns.servers)) {
	let node_domains = [];
	for (let outbound in config.outbounds) {
		let addr = null;
		if (outbound?.settings?.vnext?.[0]?.address)
			addr = outbound.settings.vnext[0].address;
		else if (outbound?.settings?.servers?.[0]?.address)
			addr = outbound.settings.servers[0].address;
		if (addr && !match(addr, /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) && !match(addr, /:/))
			push(node_domains, 'full:' + addr);
	}
	if (length(node_domains)) {
		unshift(config.dns.servers, {
			address: china_dns_server || wan_dns,
			port: 53,
			domains: node_domains
		});
	}
}

/* Clean up empty arrays */
if (isEmpty(config.dns.servers))
	delete config.dns;
if (isEmpty(config.routing.balancers))
	delete config.routing.balancers;

system('mkdir -p ' + RUN_DIR);
writefile(RUN_DIR + '/xray-c.json', sprintf('%.J\n', removeBlankAttrs(config)));
