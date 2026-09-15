export interface ParsedUA {
	os: string;
	browser: string;
}

/** Minimal UA classifier for the IP audit modal — no dependency, best effort. */
export function parseUserAgent(ua: string): ParsedUA {
	const u = ua || "";
	let os = "Unknown";
	if (/iPhone|iPad|iPod/.test(u)) os = "iOS";
	else if (/Android/.test(u)) os = "Android";
	else if (/Windows/.test(u)) os = "Windows";
	else if (/Macintosh|Mac OS X/.test(u)) os = "macOS";
	else if (/CrOS/.test(u)) os = "ChromeOS";
	else if (/Linux|X11|Ubuntu/.test(u)) os = "Linux";

	let browser = "Unknown";
	if (/Edg\//.test(u)) browser = "Edge";
	else if (/SamsungBrowser/.test(u)) browser = "Samsung Internet";
	else if (/OPR\/|Opera/.test(u)) browser = "Opera";
	else if (/Firefox\//.test(u)) browser = "Firefox";
	else if (/Chrome\//.test(u)) browser = "Chrome";
	else if (/Safari\//.test(u)) browser = "Safari";
	else if (/Dart|dart\/io/.test(u)) browser = "Instiy app";
	else if (/curl/i.test(u)) browser = "curl";
	return { os, browser };
}
