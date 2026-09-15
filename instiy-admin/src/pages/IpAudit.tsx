import React, { useCallback, useEffect, useState } from "react";
import { supabase } from "../supabaseClient";
import {
	Search,
	Globe,
	Loader,
	Ban,
	Undo2,
	Users as UsersIcon,
	MonitorSmartphone,
	Activity,
	ShieldAlert,
	ChevronLeft,
	ChevronRight,
} from "lucide-react";
import {
	Dialog,
	DialogContent,
	DialogHeader,
	DialogTitle,
	DialogFooter,
} from "../components/dialog";
import { parseUserAgent } from "../utils/userAgent";

const PAGE_SIZE = 25;

interface IpSummaryRow {
	ip_address: string;
	country: string | null;
	event_count: number;
	login_count: number;
	account_count: number;
	anonymous_event_count: number;
	first_seen: string;
	last_seen: string;
	platforms: string[] | null;
	device_models: string[] | null;
	user_ids: string[] | null;
	is_blocked: boolean;
	block_reason: string | null;
}

interface IpEventRow {
	id: string;
	event_type: string;
	user_id: string | null;
	user_agent: string | null;
	platform: string | null;
	os_version: string | null;
	device_model: string | null;
	app_version: string | null;
	country: string | null;
	created_at: string;
}

interface AccountRow {
	id: string;
	full_name: string;
	email: string;
	university: string | null;
	avatar_url: string | null;
	suspended: boolean | null;
	is_admin: boolean | null;
}

const flag = (cc?: string | null) =>
	cc && cc.length === 2
		? String.fromCodePoint(
				...[...cc.toUpperCase()].map((c) => 127397 + c.charCodeAt(0)),
			)
		: "🌐";

function timeAgo(iso: string): string {
	const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
	if (s < 60) return `${Math.floor(s)}s ago`;
	if (s < 3600) return `${Math.floor(s / 60)}m ago`;
	if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
	return `${Math.floor(s / 86400)}d ago`;
}

export const IpAudit: React.FC = () => {
	const [rows, setRows] = useState<IpSummaryRow[]>([]);
	const [total, setTotal] = useState(0);
	const [page, setPage] = useState(0);
	const [search, setSearch] = useState("");
	const [debouncedSearch, setDebouncedSearch] = useState("");
	const [anonymousOnly, setAnonymousOnly] = useState(false);
	const [loading, setLoading] = useState(true);
	const [stats, setStats] = useState({
		events7d: 0,
		anonymous7d: 0,
		blocked: 0,
	});

	// Detail modal
	const [selected, setSelected] = useState<IpSummaryRow | null>(null);
	const [events, setEvents] = useState<IpEventRow[]>([]);
	const [accounts, setAccounts] = useState<AccountRow[]>([]);
	const [loadingDetail, setLoadingDetail] = useState(false);

	// Block dialog
	const [blockTarget, setBlockTarget] = useState<IpSummaryRow | null>(null);
	const [blockReason, setBlockReason] = useState("");
	const [blockSaving, setBlockSaving] = useState(false);
	const [unblockTarget, setUnblockTarget] = useState<IpSummaryRow | null>(null);
	const [currentUserId, setCurrentUserId] = useState<string | null>(null);

	useEffect(() => {
		supabase.auth.getUser().then(({ data }) => {
			setCurrentUserId(data.user?.id ?? null);
		});
	}, []);

	// Debounce search
	useEffect(() => {
		const t = setTimeout(() => {
			setDebouncedSearch(search);
			setPage(0);
		}, 400);
		return () => clearTimeout(t);
	}, [search]);

	const fetchPage = useCallback(async () => {
		setLoading(true);
		try {
			const [sumRes, cntRes] = await Promise.all([
				supabase.rpc("get_ip_audit_summary", {
					p_offset: page * PAGE_SIZE,
					p_limit: PAGE_SIZE,
					p_search: debouncedSearch,
					p_anonymous_only: anonymousOnly,
				}),
				supabase.rpc("get_ip_audit_count", {
					p_search: debouncedSearch,
					p_anonymous_only: anonymousOnly,
				}),
			]);
			if (sumRes.error) throw sumRes.error;
			if (cntRes.error) throw cntRes.error;
			setRows((sumRes.data as IpSummaryRow[]) || []);
			setTotal(Number(cntRes.data ?? 0));
		} catch (error) {
			console.error("Error fetching IP audit:", error);
			setRows([]);
		} finally {
			setLoading(false);
		}
	}, [page, debouncedSearch, anonymousOnly]);

	useEffect(() => {
		fetchPage();
	}, [fetchPage]);

	// Stats: events in the last 7 days + anonymous subset + blocklist size
	const fetchStats = useCallback(async () => {
		try {
			const since = new Date(Date.now() - 7 * 86400_000).toISOString();
			const [ev, anon, blocked] = await Promise.all([
				supabase
					.from("ip_events")
					.select("id", { count: "exact", head: true })
					.gte("created_at", since),
				supabase
					.from("ip_events")
					.select("id", { count: "exact", head: true })
					.gte("created_at", since)
					.is("user_id", null),
				supabase
					.from("blocked_ips")
					.select("ip_address", { count: "exact", head: true }),
			]);
			setStats({
				events7d: ev.count ?? 0,
				anonymous7d: anon.count ?? 0,
				blocked: blocked.count ?? 0,
			});
		} catch (_) {}
	}, []);

	useEffect(() => {
		fetchStats();
	}, [fetchStats]);

	const openDetail = useCallback(async (row: IpSummaryRow) => {
		setSelected(row);
		setEvents([]);
		setAccounts([]);
		setLoadingDetail(true);
		try {
			const ids = row.user_ids || [];
			const [evRes, accRes] = await Promise.all([
				supabase
					.from("ip_events")
					.select(
						"id,event_type,user_id,user_agent,platform,os_version,device_model,app_version,country,created_at",
					)
					.eq("ip_address", row.ip_address)
					.order("created_at", { ascending: false })
					.limit(50),
				ids.length
					? supabase
							.from("users")
							.select(
								"id,full_name,email,university,avatar_url,suspended,is_admin",
							)
							.in("id", ids)
					: Promise.resolve({ data: [], error: null }),
			]);
			if (evRes.error) throw evRes.error;
			setEvents((evRes.data as IpEventRow[]) || []);
			setAccounts(((accRes as { data?: AccountRow[] }).data as AccountRow[]) || []);
		} catch (error) {
			console.error("Error fetching IP detail:", error);
		} finally {
			setLoadingDetail(false);
		}
	}, []);

	const blockIp = async () => {
		if (!blockTarget || !blockReason.trim()) return;
		setBlockSaving(true);
		try {
			const { error } = await supabase.from("blocked_ips").insert({
				ip_address: blockTarget.ip_address,
				reason: blockReason.trim(),
				blocked_by: currentUserId,
			});
			if (error) throw error;
			const target = blockTarget;
			setBlockTarget(null);
			setBlockReason("");
			await fetchPage();
			await fetchStats();
			if (selected?.ip_address === target.ip_address) {
				await openDetail({
					...target,
					is_blocked: true,
					block_reason: blockReason.trim(),
				});
			}
		} catch (error) {
			alert("Error blocking IP: " + (error as any).message);
		} finally {
			setBlockSaving(false);
		}
	};

	const unblockIp = async () => {
		if (!unblockTarget) return;
		setBlockSaving(true);
		try {
			const { error } = await supabase
				.from("blocked_ips")
				.delete()
				.eq("ip_address", unblockTarget.ip_address);
			if (error) throw error;
			const target = unblockTarget;
			setUnblockTarget(null);
			await fetchPage();
			await fetchStats();
			if (selected?.ip_address === target.ip_address) {
				await openDetail({ ...target, is_blocked: false, block_reason: null });
			}
		} catch (error) {
			alert("Error unblocking IP: " + (error as any).message);
		} finally {
			setBlockSaving(false);
		}
	};

	const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE));

	return (
		<div>
			<div
				style={{
					display: "flex",
					alignItems: "center",
					gap: "0.75rem",
					marginBottom: "1.5rem",
				}}
			>
				<Globe size={28} style={{ color: "hsl(var(--accent))" }} />
				<div>
					<h1 className="page-title">IP Audit</h1>
					<p style={{ marginTop: "0.2rem", fontSize: "0.85rem" }}>
						Public IP addresses using the app — devices, accounts, and blocking
					</p>
				</div>
			</div>

			{/* Stat cards */}
			<div
				style={{
					display: "grid",
					gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
					gap: "1rem",
					marginBottom: "1.5rem",
				}}
			>
				<div className="card" style={{ padding: "1rem" }}>
					<div style={{ fontSize: "0.75rem", color: "hsl(var(--text-tertiary))" }}>
						Unique IPs
					</div>
					<div style={{ fontSize: "1.5rem", fontWeight: 700 }}>{total}</div>
				</div>
				<div className="card" style={{ padding: "1rem" }}>
					<div style={{ fontSize: "0.75rem", color: "hsl(var(--text-tertiary))" }}>
						Events (7 days)
					</div>
					<div style={{ fontSize: "1.5rem", fontWeight: 700 }}>{stats.events7d}</div>
				</div>
				<div className="card" style={{ padding: "1rem" }}>
					<div style={{ fontSize: "0.75rem", color: "hsl(var(--text-tertiary))" }}>
						Anonymous events (7 days)
					</div>
					<div style={{ fontSize: "1.5rem", fontWeight: 700 }}>{stats.anonymous7d}</div>
				</div>
				<div className="card" style={{ padding: "1rem" }}>
					<div style={{ fontSize: "0.75rem", color: "hsl(var(--text-tertiary))" }}>
						Blocked IPs
					</div>
					<div style={{ fontSize: "1.5rem", fontWeight: 700, color: "#dc2626" }}>
						{stats.blocked}
					</div>
				</div>
			</div>

			{/* Search + anonymous filter */}
			<div className="card" style={{ marginBottom: "1.5rem", padding: "0.875rem" }}>
				<div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap", alignItems: "center" }}>
					<div style={{ position: "relative", width: "100%", maxWidth: "360px" }}>
						<Search
							size={16}
							style={{
								position: "absolute",
								left: "10px",
								top: "50%",
								transform: "translateY(-50%)",
								color: "hsl(var(--text-tertiary))",
							}}
						/>
						<input
							type="text"
							className="form-control"
							style={{ paddingLeft: "2.25rem" }}
							placeholder="Search by IP, account name, or email..."
							value={search}
							onChange={(e) => setSearch(e.target.value)}
						/>
					</div>
					<label
						style={{
							display: "flex",
							alignItems: "center",
							gap: "0.4rem",
							fontSize: "0.85rem",
							cursor: "pointer",
							userSelect: "none",
						}}
					>
						<input
							type="checkbox"
							checked={anonymousOnly}
							onChange={(e) => {
								setAnonymousOnly(e.target.checked);
								setPage(0);
							}}
						/>
						Anonymous only
					</label>
				</div>
			</div>

			{loading ? (
				<div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "40vh" }}>
					<Loader className="spin" size={28} style={{ color: "hsl(var(--accent))" }} />
				</div>
			) : (
				<div className="table-container">
					<table className="table">
						<thead>
							<tr>
								<th>IP Address</th>
								<th>Country</th>
								<th>Platforms</th>
								<th>Accounts</th>
								<th>Events</th>
								<th>First seen</th>
								<th>Last seen</th>
								<th style={{ textAlign: "right" }}>Actions</th>
							</tr>
						</thead>
						<tbody>
							{rows.length === 0 ? (
								<tr>
									<td
										colSpan={8}
										style={{ textAlign: "center", color: "hsl(var(--text-tertiary))", padding: "2rem" }}
									>
										No IP activity recorded yet
									</td>
								</tr>
							) : (
								rows.map((row) => (
									<tr
										key={row.ip_address}
										style={{ cursor: "pointer" }}
										onClick={() => openDetail(row)}
									>
										<td style={{ fontWeight: 600, fontSize: "0.85rem" }}>
											{row.ip_address}
											{row.is_blocked && (
												<span className="badge badge-danger" style={{ marginLeft: 6, fontSize: "0.65rem", padding: "1px 5px" }}>
													Blocked
												</span>
											)}
										</td>
										<td style={{ fontSize: "0.85rem" }}>
											{flag(row.country)} {row.country || "—"}
										</td>
										<td style={{ fontSize: "0.8rem" }}>
											{(row.platforms || []).join(", ") || "—"}
										</td>
										<td style={{ fontSize: "0.85rem" }}>
											{row.account_count === 0 ? (
												<span className="badge" style={{ fontSize: "0.65rem" }}>
													Anonymous
												</span>
											) : (
												`${row.account_count} account${row.account_count === 1 ? "" : "s"}`
											)}
											{row.anonymous_event_count > 0 && (
												<div style={{ fontSize: "0.7rem", color: "hsl(var(--text-tertiary))" }}>
													+ anonymous activity
												</div>
											)}
										</td>
										<td style={{ fontSize: "0.85rem" }}>{row.event_count}</td>
										<td style={{ fontSize: "0.8rem" }}>{timeAgo(row.first_seen)}</td>
										<td style={{ fontSize: "0.8rem" }}>{timeAgo(row.last_seen)}</td>
										<td style={{ textAlign: "right" }} onClick={(e) => e.stopPropagation()}>
											{row.is_blocked ? (
												<button className="btn btn-secondary" onClick={() => setUnblockTarget(row)}>
													<Undo2 size={14} /> Unblock
												</button>
											) : (
												<button className="btn btn-danger" onClick={() => { setBlockTarget(row); setBlockReason(""); }}>
													<Ban size={14} /> Block
												</button>
											)}
										</td>
									</tr>
								))
							)}
						</tbody>
					</table>
				</div>
			)}

			{/* Pagination */}
			<div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginTop: "1rem" }}>
				<span style={{ fontSize: "0.8rem", color: "hsl(var(--text-tertiary))" }}>
					Page {page + 1} of {pageCount} ({total} IPs)
				</span>
				<div style={{ display: "flex", gap: "0.5rem" }}>
					<button className="btn btn-secondary" disabled={page === 0} onClick={() => setPage((p) => p - 1)}>
						<ChevronLeft size={14} /> Prev
					</button>
					<button
						className="btn btn-secondary"
						disabled={page + 1 >= pageCount}
						onClick={() => setPage((p) => p + 1)}
					>
						Next <ChevronRight size={14} />
					</button>
				</div>
			</div>

			{/* Detail modal */}
			<Dialog open={!!selected} onOpenChange={(o) => !o && setSelected(null)}>
				<DialogContent style={{ maxWidth: "680px" }}>
					{selected && (
						<>
							<DialogHeader>
								<DialogTitle style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
									{flag(selected.country)} {selected.ip_address}
									{selected.is_blocked && (
										<span className="badge badge-danger" style={{ fontSize: "0.65rem" }}>
											Blocked
										</span>
									)}
								</DialogTitle>
							</DialogHeader>

							{loadingDetail ? (
								<div style={{ display: "flex", justifyContent: "center", padding: "2rem" }}>
									<Loader className="spin" size={24} style={{ color: "hsl(var(--accent))" }} />
								</div>
							) : (
								<>
									{/* Device section */}
									<section style={{ marginTop: "1rem" }}>
										<h3 style={{ display: "flex", alignItems: "center", gap: "0.4rem", fontSize: "0.9rem", marginBottom: "0.5rem" }}>
											<MonitorSmartphone size={15} /> Devices
										</h3>
										{(selected.device_models || []).length > 0 && (
											<p style={{ fontSize: "0.85rem", marginBottom: "0.25rem" }}>
												<strong>Models:</strong> {(selected.device_models || []).join(", ")}
											</p>
										)}
										<p style={{ fontSize: "0.85rem", marginBottom: "0.25rem" }}>
											<strong>Platforms:</strong> {(selected.platforms || []).join(", ") || "—"}
										</p>
										<div style={{ display: "flex", flexWrap: "wrap", gap: "0.4rem", marginTop: "0.5rem" }}>
											{[...new Set(events.map((e) => e.user_agent).filter(Boolean))].slice(0, 8).map((ua) => {
												const p = parseUserAgent(ua as string);
												return (
													<span key={ua} className="badge" style={{ fontSize: "0.7rem" }}>
														{p.os} · {p.browser}
													</span>
												);
											})}
										</div>
									</section>

									{/* Accounts section */}
									<section style={{ marginTop: "1.25rem" }}>
										<h3 style={{ display: "flex", alignItems: "center", gap: "0.4rem", fontSize: "0.9rem", marginBottom: "0.5rem" }}>
											<UsersIcon size={15} /> Associated accounts ({accounts.length})
										</h3>
										{accounts.length === 0 ? (
											<p style={{ fontSize: "0.85rem", color: "hsl(var(--text-tertiary))" }}>
												No signed-in account has been seen on this IP
												{selected.anonymous_event_count > 0
													? ` — ${selected.anonymous_event_count} anonymous event(s) instead`
													: ""}
												.
											</p>
										) : (
											accounts.map((a) => (
												<div
													key={a.id}
													style={{
														display: "flex",
														alignItems: "center",
														gap: "0.625rem",
														padding: "0.5rem 0",
														borderBottom: "1px solid hsl(var(--border))",
													}}
												>
													<img
														src={
															a.avatar_url ||
															"https://api.dicebear.com/7.x/bottts/svg?seed=" + a.email
														}
														alt={a.full_name}
														style={{
															width: "30px",
															height: "30px",
															borderRadius: "50%",
															border: "1px solid hsl(var(--border))",
															objectFit: "cover",
														}}
													/>
													<div style={{ flex: 1, minWidth: 0 }}>
														<div style={{ fontWeight: 600, fontSize: "0.85rem" }}>
															{a.full_name}
															{a.suspended && (
																<span className="badge badge-danger" style={{ marginLeft: 6, fontSize: "0.6rem", padding: "1px 4px" }}>
																	Suspended
																</span>
															)}
															{a.is_admin && (
																<span className="badge" style={{ marginLeft: 6, fontSize: "0.6rem", padding: "1px 4px" }}>
																	Admin
																</span>
															)}
														</div>
														<div style={{ fontSize: "0.75rem", color: "hsl(var(--text-tertiary))" }}>
															{a.email}
															{a.university ? ` · ${a.university}` : ""}
														</div>
													</div>
													<a
														href={`/users?q=${encodeURIComponent(a.email)}`}
														style={{ fontSize: "0.75rem", color: "hsl(var(--accent))" }}
													>
														View in Users
													</a>
												</div>
											))
										)}
									</section>

									{/* Activity section */}
									<section style={{ marginTop: "1.25rem" }}>
										<h3 style={{ display: "flex", alignItems: "center", gap: "0.4rem", fontSize: "0.9rem", marginBottom: "0.5rem" }}>
											<Activity size={15} /> Recent activity ({events.length})
										</h3>
										<div style={{ maxHeight: "220px", overflowY: "auto" }}>
											{events.map((e) => (
												<div
													key={e.id}
													style={{
														display: "flex",
														justifyContent: "space-between",
														gap: "0.5rem",
														padding: "0.35rem 0",
														borderBottom: "1px solid hsl(var(--border))",
														fontSize: "0.78rem",
													}}
												>
													<span>
														<span className="badge" style={{ fontSize: "0.6rem", marginRight: 6 }}>
															{e.event_type}
														</span>
														{e.user_id ? "signed-in" : "anonymous"}
														{e.device_model ? ` · ${e.device_model}` : ""}
														{e.platform ? ` · ${e.platform}` : ""}
													</span>
													<span style={{ color: "hsl(var(--text-tertiary))", whiteSpace: "nowrap" }}>
														{timeAgo(e.created_at)}
													</span>
												</div>
											))}
										</div>
									</section>
								</>
							)}
						</>
					)}
				</DialogContent>
			</Dialog>

			{/* Block dialog */}
			<Dialog open={!!blockTarget} onOpenChange={(o) => !o && setBlockTarget(null)}>
				<DialogContent>
					<DialogHeader>
						<DialogTitle style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
							<ShieldAlert size={18} /> Block {blockTarget?.ip_address}
						</DialogTitle>
					</DialogHeader>
					<div
						className="card"
						style={{
							padding: "0.75rem",
							marginTop: "0.75rem",
							backgroundColor: "#fef3c7",
							fontSize: "0.8rem",
						}}
					>
						<strong>Heads-up:</strong> {blockTarget?.account_count ?? 0} account(s) and{" "}
						{blockTarget?.event_count ?? 0} event(s) have been seen from this IP. Campus
						networks often share one public IP — blocking it affects everyone behind it.
					</div>
					<textarea
						className="form-control"
						style={{ marginTop: "0.75rem", minHeight: "70px" }}
						placeholder="Reason (required) — shown to the blocked user"
						value={blockReason}
						onChange={(e) => setBlockReason(e.target.value)}
					/>
					<DialogFooter>
						<button className="btn btn-secondary" onClick={() => setBlockTarget(null)}>
							Cancel
						</button>
						<button
							className="btn btn-danger"
							disabled={!blockReason.trim() || blockSaving}
							onClick={blockIp}
						>
							{blockSaving ? <Loader className="spin" size={14} /> : <Ban size={14} />} Block IP
						</button>
					</DialogFooter>
				</DialogContent>
			</Dialog>

			{/* Unblock dialog */}
			<Dialog open={!!unblockTarget} onOpenChange={(o) => !o && setUnblockTarget(null)}>
				<DialogContent>
					<DialogHeader>
						<DialogTitle>Unblock {unblockTarget?.ip_address}</DialogTitle>
					</DialogHeader>
					<p style={{ fontSize: "0.85rem", marginTop: "0.5rem" }}>
						Clients on this IP will regain access on their next app launch. This cannot
						be undone faster than the worker's 60-second blocklist cache.
					</p>
					<DialogFooter>
						<button className="btn btn-secondary" onClick={() => setUnblockTarget(null)}>
							Cancel
						</button>
						<button className="btn btn-primary" disabled={blockSaving} onClick={unblockIp}>
							{blockSaving ? <Loader className="spin" size={14} /> : <Undo2 size={14} />} Unblock
						</button>
					</DialogFooter>
				</DialogContent>
			</Dialog>
		</div>
	);
};
