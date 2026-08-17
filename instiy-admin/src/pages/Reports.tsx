import React, { useEffect, useState, useCallback } from "react";
import { supabase } from "../supabaseClient";
import {
	Flag,
	X,
	Eye,
	Loader,
	CheckCircle,
	XCircle,
	Clock,
	AlertTriangle,
	Package,
	Ban,
	Unlock,
	Circle,
} from "lucide-react";
import {
	Dialog,
	DialogContent,
	DialogHeader,
	DialogTitle,
	DialogClose,
} from "../components/dialog";
import { useAlert, useConfirm } from '../components/use-alert';
import { formatCurrency } from "../utils/format";

type ReportStatus = "pending" | "reviewed" | "resolved" | "dismissed" | "";

const STATUS_TABS: { label: string; value: ReportStatus }[] = [
	{ label: "All", value: "" },
	{ label: "Pending", value: "pending" },
	{ label: "Reviewed", value: "reviewed" },
	{ label: "Resolved", value: "resolved" },
	{ label: "Dismissed", value: "dismissed" },
];

const CATEGORY_LABELS: Record<string, string> = {
	spam: "Spam",
	harassment: "Harassment",
	scam: "Scam",
	inappropriate_content: "Inappropriate Content",
	fake_account: "Fake Account",
	hate_speech: "Hate Speech",
	violence: "Violence",
	illegal_activity: "Illegal Activity",
	counterfeit: "Counterfeit / Fake",
	misleading_listing: "Misleading Listing",
	prohibited_item: "Prohibited Item",
	product_scam: "Scam / Fraud",
	stolen_property: "Stolen Property",
	price_gouging: "Price Gouging",
	other: "Other",
};

const CATEGORY_COLORS: Record<string, string> = {
	spam: "hsl(210, 80%, 50%)",
	harassment: "hsl(0, 75%, 55%)",
	scam: "hsl(30, 90%, 50%)",
	inappropriate_content: "hsl(280, 70%, 55%)",
	fake_account: "hsl(190, 80%, 45%)",
	hate_speech: "hsl(0, 85%, 50%)",
	violence: "hsl(15, 85%, 50%)",
	illegal_activity: "hsl(260, 75%, 50%)",
	counterfeit: "hsl(340, 75%, 50%)",
	misleading_listing: "hsl(25, 85%, 50%)",
	prohibited_item: "hsl(0, 80%, 45%)",
	stolen_property: "hsl(270, 70%, 50%)",
	price_gouging: "hsl(40, 90%, 45%)",
	other: "hsl(220, 10%, 50%)",
};

const COMPLAINT_STATUS_LABELS: Record<string, string> = {
	pending: "Pending",
	reviewed: "Reviewed",
	resolved: "Resolved",
	dismissed: "Dismissed",
};

export const Reports: React.FC = () => {
	const [reports, setReports] = useState<any[]>([]);
	const [loading, setLoading] = useState(true);
	const [fetchError, setFetchError] = useState<string | null>(null);
	const [activeTab, setActiveTab] = useState<ReportStatus>("");
	const [selectedReport, setSelectedReport] = useState<any>(null);
	const [actionLoading, setActionLoading] = useState(false);
	const [adminNotes, setAdminNotes] = useState("");
	const [statusUpdate, setStatusUpdate] = useState<{
		id: string;
		status: string;
	} | null>(null);
	const [suspendingUserId, setSuspendingUserId] = useState<string | null>(null);
	const { alert, AlertComponent } = useAlert();
	const { confirm, ConfirmComponent } = useConfirm();

	const fetchReports = useCallback(async () => {
		try {
			setLoading(true);
			setFetchError(null);

			const { data, error } = await supabase.rpc("get_admin_reports");
			if (error) throw error;

			const reshaped = (data || []).map((row: any) => ({
				id: row.report_id,
				category: row.category,
				description: row.description,
				conversation_id: row.conversation_id,
				product_id: row.product_id,
				status: row.status,
				admin_notes: row.admin_notes,
				is_read: row.is_read,
				created_at: row.created_at,
				updated_at: row.updated_at,
				reporter: {
					id: row.reporter_id,
					full_name: row.reporter_name,
					avatar_url: row.reporter_avatar,
					university: row.reporter_university,
				},
				reported: {
					id: row.reported_user_id,
					full_name: row.reported_name,
					avatar_url: row.reported_avatar,
					university: row.reported_university,
					suspended: row.reported_suspended,
				},
				product: row.product_id
					? {
							id: row.product_id,
							title: row.product_title,
							images: row.product_image ? [row.product_image] : [],
							price: row.product_price,
						}
					: null,
				complaint: row.complaint_id
					? {
							id: row.complaint_id,
							text: row.complaint_text,
							status: row.complaint_status,
						}
					: null,
			}));

			const filtered = activeTab
				? reshaped.filter((r: any) => r.status === activeTab)
				: reshaped;

			setReports(filtered);
		} catch (error: any) {
			console.error("Error fetching reports:", error);
			setFetchError(error?.message || "Failed to load reports");
		} finally {
			setLoading(false);
		}
	}, [activeTab]);

	useEffect(() => {
		fetchReports();
	}, [fetchReports]);

	const markAsRead = async (reportId: string) => {
		try {
			await supabase.rpc("mark_report_read", { report_uuid: reportId });
			setReports((prev) =>
				prev.map((r) => (r.id === reportId ? { ...r, is_read: true } : r)),
			);
		} catch (e) {
			console.error("Failed to mark report as read:", e);
		}
	};

	const handleStatusUpdate = async (reportId: string, newStatus: string) => {
		try {
			setActionLoading(true);
			const { error } = await supabase
				.from("reports")
				.update({
					status: newStatus,
					admin_notes: adminNotes.trim() || null,
				})
				.eq("id", reportId);

			if (error) throw error;

			setStatusUpdate(null);
			setAdminNotes("");
			setSelectedReport(null);
			await fetchReports();
		} catch (error) {
			alert('Error', { description: (error as any).message, variant: 'danger' });
		} finally {
			setActionLoading(false);
		}
	};

	const handleSuspendUser = (userId: string, reportId?: string) => {
		confirm(
			"Suspend User",
			async () => {
				try {
					setSuspendingUserId(userId);
					const updateData: Record<string, any> = {
						suspended: true,
						suspended_at: new Date().toISOString(),
					};
					if (reportId) {
						updateData.suspended_report_id = reportId;
					}
					const { error } = await supabase
						.from("users")
						.update(updateData)
						.eq("id", userId);
					if (error) throw error;
					await fetchReports();
					// Update selected report if open
					setSelectedReport((prev: any) =>
						prev
							? {
									...prev,
									reported: { ...prev.reported, suspended: true },
								}
							: null,
					);
				} catch (error) {
					alert('Error', { description: 'Error suspending user: ' + (error as any).message, variant: 'danger' });
				} finally {
					setSuspendingUserId(null);
				}
			},
			{ variant: 'danger', confirmLabel: 'Suspend' }
		);
	};

	const handleUnsuspendUser = async (userId: string) => {
		try {
			setSuspendingUserId(userId);
			const { error } = await supabase
				.from("users")
				.update({ suspended: false, suspended_at: null })
				.eq("id", userId);
			if (error) throw error;
			await fetchReports();
			setSelectedReport((prev: any) =>
				prev
					? {
							...prev,
							reported: { ...prev.reported, suspended: false },
						}
					: null,
			);
		} catch (error) {
			alert("Error unsuspending user", { description: (error as any).message, variant: 'danger' });
		} finally {
			setSuspendingUserId(null);
		}
	};

	const getStatusBadge = (status: string) => {
		switch (status) {
			case "pending":
				return (
					<span className="badge badge-warning">
						<Clock size={10} style={{ marginRight: 4 }} /> Pending
					</span>
				);
			case "reviewed":
				return (
					<span className="badge badge-info">
						<Eye size={10} style={{ marginRight: 4 }} /> Reviewed
					</span>
				);
			case "resolved":
				return (
					<span className="badge badge-success">
						<CheckCircle size={10} style={{ marginRight: 4 }} /> Resolved
					</span>
				);
			case "dismissed":
				return (
					<span className="badge badge-secondary">
						<XCircle size={10} style={{ marginRight: 4 }} /> Dismissed
					</span>
				);
			default:
				return <span className="badge">{status}</span>;
		}
	};

	const getCategoryBadge = (category: string) => {
		const color = CATEGORY_COLORS[category] || CATEGORY_COLORS.other;
		const label = CATEGORY_LABELS[category] || category;
		return (
			<span
				style={{
					display: "inline-flex",
					alignItems: "center",
					gap: 4,
					padding: "2px 8px",
					borderRadius: "12px",
					fontSize: "0.72rem",
					fontWeight: 600,
					color: "white",
					backgroundColor: color,
				}}
			>
				{label}
			</span>
		);
	};

	const filteredCount = reports.length;
	const unreadCount = reports.filter((r) => !r.is_read).length;

	return (
		<div className="animated-fade-in">
			<div className="page-header">
				<div>
					<h1 className="page-title">Reports</h1>
					<p
						style={{
							color: "hsl(var(--text-tertiary))",
							marginTop: "0.2rem",
							fontSize: "0.85rem",
						}}
					>
						Review and manage user &amp; product reports
						{unreadCount > 0 && (
							<span
								style={{
									marginLeft: "0.5rem",
									display: "inline-flex",
									alignItems: "center",
									justifyContent: "center",
									background: "hsl(var(--danger))",
									color: "white",
									borderRadius: "10px",
									minWidth: "20px",
									height: "20px",
									padding: "0 6px",
									fontSize: "0.7rem",
									fontWeight: 700,
								}}
							>
								{unreadCount} unread
							</span>
						)}
					</p>
				</div>
			</div>

			{/* Status Tabs */}
			<div
				className="card"
				style={{ marginBottom: "1.5rem", padding: "0.5rem" }}
			>
				<div style={{ display: "flex", gap: "0.25rem", flexWrap: "wrap" }}>
					{STATUS_TABS.map((tab) => (
						<button
							key={tab.value}
							className={`btn btn-sm ${activeTab === tab.value ? "btn-primary" : "btn-secondary"}`}
							onClick={() => setActiveTab(tab.value)}
						>
							{tab.label}
							{tab.value === "" && (
								<span style={{ marginLeft: 4, opacity: 0.7 }}>
									({filteredCount})
								</span>
							)}
						</button>
					))}
				</div>
			</div>

			{loading ? (
				<div
					style={{
						display: "flex",
						alignItems: "center",
						justifyContent: "center",
						height: "40vh",
					}}
				>
					<Loader
						className="spin"
						size={28}
						style={{ color: "hsl(var(--accent))" }}
					/>
				</div>
			) : fetchError ? (
				<div className="card" style={{ textAlign: "center", padding: "3rem" }}>
					<AlertTriangle
						size={48}
						style={{ color: "hsl(var(--danger-hover))", margin: "0 auto 1rem" }}
					/>
					<p
						style={{
							color: "hsl(var(--danger-hover))",
							fontWeight: 600,
							marginBottom: "0.5rem",
						}}
					>
						Failed to load reports
					</p>
					<p
						style={{
							color: "hsl(var(--text-tertiary))",
							fontSize: "0.85rem",
							marginBottom: "1rem",
						}}
					>
						{fetchError}
					</p>
					<button
						className="btn btn-primary"
						style={{ marginTop: "1rem" }}
						onClick={fetchReports}
					>
						Retry
					</button>
				</div>
			) : reports.length === 0 ? (
				<div className="card" style={{ textAlign: "center", padding: "3rem" }}>
					<Flag
						size={48}
						style={{
							color: "hsl(var(--text-tertiary))",
							margin: "0 auto 1rem",
						}}
					/>
					<p style={{ color: "hsl(var(--text-tertiary))" }}>No reports found</p>
				</div>
			) : (
				<div className="table-container">
					<table className="table">
						<thead>
							<tr>
								<th style={{ width: "18px" }}></th>
								<th>Reporter</th>
								<th>Reported User</th>
								<th>Listing</th>
								<th>Category</th>
								<th>Submitted</th>
								<th>Status</th>
								<th style={{ textAlign: "right" }}>Actions</th>
							</tr>
						</thead>
						<tbody>
							{reports.map((r) => (
								<tr
									key={r.id}
									style={
										!r.is_read
											? { background: "hsl(var(--accent) / 0.03)" }
											: undefined
									}
								>
									<td>
										{!r.is_read && (
											<Circle
												size={8}
												fill="hsl(var(--accent))"
												color="hsl(var(--accent))"
											/>
										)}
									</td>
									<td>
										<div
											style={{
												display: "flex",
												alignItems: "center",
												gap: "0.625rem",
											}}
										>
											<img
												src={
													r.reporter?.avatar_url ||
													"https://api.dicebear.com/7.x/bottts/svg?seed=" +
														r.reporter?.id
												}
												alt={r.reporter?.full_name}
												style={{
													width: "34px",
													height: "34px",
													borderRadius: "50%",
													border: "1px solid hsl(var(--border))",
													objectFit: "cover",
												}}
											/>
											<div>
												<div style={{ fontWeight: 600, fontSize: "0.85rem" }}>
													{r.reporter?.full_name}
												</div>
												<div
													style={{
														fontSize: "0.72rem",
														color: "hsl(var(--text-tertiary))",
													}}
												>
													{r.reporter?.university}
												</div>
											</div>
										</div>
									</td>
									<td>
										<div
											style={{
												display: "flex",
												alignItems: "center",
												gap: "0.625rem",
											}}
										>
											<img
												src={
													r.reported?.avatar_url ||
													"https://api.dicebear.com/7.x/bottts/svg?seed=" +
														r.reported?.id
												}
												alt={r.reported?.full_name}
												style={{
													width: "34px",
													height: "34px",
													borderRadius: "50%",
													border: "1px solid hsl(var(--border))",
													objectFit: "cover",
												}}
											/>
											<div>
												<div style={{ fontWeight: 600, fontSize: "0.85rem" }}>
													{r.reported?.full_name}
													{r.reported?.suspended && (
														<span
															className="badge badge-danger"
															style={{
																marginLeft: 6,
																fontSize: "0.65rem",
																padding: "1px 5px",
															}}
														>
															Suspended
														</span>
													)}
												</div>
												<div
													style={{
														fontSize: "0.72rem",
														color: "hsl(var(--text-tertiary))",
													}}
												>
													{r.reported?.university}
												</div>
											</div>
										</div>
									</td>
									<td>
										{r.product ? (
											<div
												style={{
													display: "flex",
													alignItems: "center",
													gap: "0.5rem",
												}}
											>
												{r.product.images?.[0] ? (
													<img
														src={r.product.images[0]}
														alt=""
														style={{
															width: "34px",
															height: "34px",
															borderRadius: "6px",
															objectFit: "cover",
															border: "1px solid hsl(var(--border))",
														}}
													/>
												) : (
													<div
														style={{
															width: "34px",
															height: "34px",
															borderRadius: "6px",
															background: "hsl(var(--bg-surface))",
															display: "flex",
															alignItems: "center",
															justifyContent: "center",
														}}
													>
														<Package
															size={14}
															style={{ color: "hsl(var(--text-tertiary))" }}
														/>
													</div>
												)}
												<div>
													<div
														style={{
															fontWeight: 600,
															fontSize: "0.82rem",
															maxWidth: "140px",
															overflow: "hidden",
															textOverflow: "ellipsis",
															whiteSpace: "nowrap",
														}}
													>
														{r.product.title}
													</div>
													{r.product.price != null && (
														<div
															style={{
																fontSize: "0.72rem",
																color: "hsl(var(--text-tertiary))",
															}}
														>
															GH&#162; {formatCurrency(r.product.price)}
														</div>
													)}
												</div>
											</div>
										) : (
											<span
												style={{
													fontSize: "0.78rem",
													color: "hsl(var(--text-tertiary))",
												}}
											>
												&#8212;
											</span>
										)}
									</td>
									<td>{getCategoryBadge(r.category)}</td>
									<td
										style={{
											color: "hsl(var(--text-tertiary))",
											fontSize: "0.8rem",
										}}
									>
										{new Date(r.created_at).toLocaleDateString()}
									</td>
									<td>{getStatusBadge(r.status)}</td>
									<td>
										<div
											style={{
												display: "flex",
												gap: "0.375rem",
												justifyContent: "flex-end",
											}}
										>
											<button
												className="btn btn-secondary btn-sm"
												onClick={() => {
													setSelectedReport(r);
													setAdminNotes(r.admin_notes || "");
													if (!r.is_read) markAsRead(r.id);
												}}
											>
												<Eye size={13} /> View
											</button>
											{r.status === "pending" && (
												<button
													className="btn btn-primary btn-sm"
													onClick={() =>
														setStatusUpdate({ id: r.id, status: "reviewed" })
													}
												>
													<CheckCircle size={13} /> Mark Reviewed
												</button>
											)}
										</div>
									</td>
								</tr>
							))}
						</tbody>
					</table>
				</div>
			)}

			{/* Detail Drawer */}
			{selectedReport && (
				<div
					className="drawer-backdrop"
					onClick={() => setSelectedReport(null)}
				>
					<div
						className="drawer"
						onClick={(e) => e.stopPropagation()}
						style={{ maxWidth: "560px" }}
					>
						<div
							style={{
								display: "flex",
								justifyContent: "space-between",
								alignItems: "center",
								borderBottom: "1px solid hsl(var(--border))",
								paddingBottom: "0.875rem",
							}}
						>
							<h2
								style={{ fontSize: "1.2rem", fontFamily: "var(--font-title)" }}
							>
								Report Details
							</h2>
							<button
								style={{
									background: "none",
									border: "none",
									cursor: "pointer",
									color: "hsl(var(--text-secondary))",
									padding: "4px",
								}}
								onClick={() => setSelectedReport(null)}
							>
								<X size={20} />
							</button>
						</div>

						{/* Reporter Info */}
						<div
							className="card"
							style={{ background: "hsl(var(--bg-surface))" }}
						>
							<h4
								style={{
									fontSize: "0.78rem",
									color: "hsl(var(--text-tertiary))",
									textTransform: "uppercase",
									letterSpacing: "0.05em",
									fontWeight: 600,
									marginBottom: "0.75rem",
								}}
							>
								Reporter
							</h4>
							<div
								style={{
									display: "flex",
									alignItems: "center",
									gap: "0.75rem",
								}}
							>
								<img
									src={
										selectedReport.reporter?.avatar_url ||
										"https://api.dicebear.com/7.x/bottts/svg?seed=" +
											selectedReport.reporter?.id
									}
									alt=""
									style={{
										width: "40px",
										height: "40px",
										borderRadius: "50%",
										objectFit: "cover",
									}}
								/>
								<div>
									<div style={{ fontWeight: 600, fontSize: "0.85rem" }}>
										{selectedReport.reporter?.full_name}
									</div>
									<div
										style={{
											fontSize: "0.75rem",
											color: "hsl(var(--text-tertiary))",
										}}
									>
										{selectedReport.reporter?.university}
									</div>
								</div>
							</div>
						</div>

						{/* Reported User Info + Suspend Action */}
						<div
							className="card"
							style={{ background: "hsl(var(--bg-surface))" }}
						>
							<div
								style={{
									display: "flex",
									justifyContent: "space-between",
									alignItems: "center",
									marginBottom: "0.75rem",
								}}
							>
								<h4
									style={{
										fontSize: "0.78rem",
										color: "hsl(var(--text-tertiary))",
										textTransform: "uppercase",
										letterSpacing: "0.05em",
										fontWeight: 600,
										margin: 0,
									}}
								>
									Reported User
								</h4>
								{selectedReport.reported?.suspended ? (
									<button
										className="btn btn-success btn-sm"
										onClick={() =>
											handleUnsuspendUser(selectedReport.reported.id)
										}
										disabled={suspendingUserId === selectedReport.reported.id}
									>
										{suspendingUserId === selectedReport.reported.id ? (
											<Loader className="spin" size={12} />
										) : (
											<Unlock size={12} />
										)}
										Unsuspend
									</button>
								) : (
									<button
										className="btn btn-danger btn-sm"
										onClick={() =>
											handleSuspendUser(selectedReport.reported.id, selectedReport.id)
										}
										disabled={suspendingUserId === selectedReport.reported.id}
									>
										{suspendingUserId === selectedReport.reported.id ? (
											<Loader className="spin" size={12} />
										) : (
											<Ban size={12} />
										)}
										Suspend
									</button>
								)}
							</div>
							<div
								style={{
									display: "flex",
									alignItems: "center",
									gap: "0.75rem",
								}}
							>
								<img
									src={
										selectedReport.reported?.avatar_url ||
										"https://api.dicebear.com/7.x/bottts/svg?seed=" +
											selectedReport.reported?.id
									}
									alt=""
									style={{
										width: "40px",
										height: "40px",
										borderRadius: "50%",
										objectFit: "cover",
									}}
								/>
								<div>
									<div style={{ fontWeight: 600, fontSize: "0.85rem" }}>
										{selectedReport.reported?.full_name}
										{selectedReport.reported?.suspended && (
											<span
												className="badge badge-danger"
												style={{
													marginLeft: 6,
													fontSize: "0.65rem",
													padding: "1px 5px",
												}}
											>
												Suspended
											</span>
										)}
									</div>
									<div
										style={{
											fontSize: "0.75rem",
											color: "hsl(var(--text-tertiary))",
										}}
									>
										{selectedReport.reported?.university}
									</div>
								</div>
							</div>
						</div>

						{/* Complaint from user (if any) */}
						{selectedReport.complaint && (
							<div
								className="card"
								style={{ borderLeft: "3px solid hsl(var(--accent))" }}
							>
								<h4
									style={{
										fontSize: "0.78rem",
										color: "hsl(var(--text-tertiary))",
										textTransform: "uppercase",
										letterSpacing: "0.05em",
										fontWeight: 600,
										marginBottom: "0.5rem",
									}}
								>
									User Complaint
								</h4>
								<p
									style={{
										fontSize: "0.85rem",
										lineHeight: "1.5",
										marginBottom: "0.5rem",
									}}
								>
									{selectedReport.complaint.text}
								</p>
								<div
									style={{
										display: "flex",
										alignItems: "center",
										gap: "0.5rem",
									}}
								>
									<span
										style={{
											fontSize: "0.75rem",
											color: "hsl(var(--text-tertiary))",
										}}
									>
										Status:
									</span>
									<span
										className={`badge ${selectedReport.complaint.status === "pending" ? "badge-warning" : selectedReport.complaint.status === "resolved" ? "badge-success" : "badge-secondary"}`}
										style={{ fontSize: "0.68rem", padding: "1px 6px" }}
									>
										{COMPLAINT_STATUS_LABELS[selectedReport.complaint.status] ||
											selectedReport.complaint.status}
									</span>
								</div>
							</div>
						)}

						{/* Reported Product (if product report) */}
						{selectedReport.product && (
							<div
								className="card"
								style={{ background: "hsl(var(--bg-surface))" }}
							>
								<h4
									style={{
										fontSize: "0.78rem",
										color: "hsl(var(--text-tertiary))",
										textTransform: "uppercase",
										letterSpacing: "0.05em",
										fontWeight: 600,
										marginBottom: "0.75rem",
									}}
								>
									Reported Listing
								</h4>
								<div
									style={{
										display: "flex",
										alignItems: "center",
										gap: "0.75rem",
									}}
								>
									{selectedReport.product.images?.[0] ? (
										<img
											src={selectedReport.product.images[0]}
											alt=""
											style={{
												width: "56px",
												height: "56px",
												borderRadius: "8px",
												objectFit: "cover",
												border: "1px solid hsl(var(--border))",
											}}
										/>
									) : (
										<div
											style={{
												width: "56px",
												height: "56px",
												borderRadius: "8px",
												background: "hsl(var(--border))",
												display: "flex",
												alignItems: "center",
												justifyContent: "center",
											}}
										>
											<Package
												size={20}
												style={{ color: "hsl(var(--text-tertiary))" }}
											/>
										</div>
									)}
									<div>
										<div style={{ fontWeight: 600, fontSize: "0.9rem" }}>
											{selectedReport.product.title}
										</div>
										{selectedReport.product.price != null && (
											<div
												style={{
													fontSize: "0.85rem",
													color: "hsl(var(--accent))",
													fontWeight: 600,
												}}
											>
												GH&#162;{" "}
												{formatCurrency(selectedReport.product.price)}
											</div>
										)}
										<a
											href={`/products?id=${selectedReport.product.id}`}
											style={{
												fontSize: "0.75rem",
												color: "hsl(var(--accent))",
												textDecoration: "none",
											}}
										>
											View product &rarr;
										</a>
									</div>
								</div>
							</div>
						)}

						{/* Report Details */}
						<div className="card">
							<h4
								style={{
									fontSize: "0.78rem",
									color: "hsl(var(--text-tertiary))",
									textTransform: "uppercase",
									letterSpacing: "0.05em",
									fontWeight: 600,
									marginBottom: "0.75rem",
								}}
							>
								Report Information
							</h4>
							{(
								[
									["Category", getCategoryBadge(selectedReport.category)],
									["Status", getStatusBadge(selectedReport.status)],
									[
										"Submitted",
										new Date(selectedReport.created_at).toLocaleString(),
									],
									selectedReport.conversation_id
										? ["Conversation ID", selectedReport.conversation_id]
										: null,
									selectedReport.product_id
										? [
												"Type",
												<span
													key="type"
													style={{
														display: "inline-flex",
														alignItems: "center",
														gap: 4,
														fontWeight: 500,
													}}
												>
													<Package size={12} /> Product Report
												</span>,
											]
										: null,
								].filter(Boolean) as [string, React.ReactNode][]
							).map(([label, value]) => (
								<div
									key={label}
									style={{
										display: "flex",
										justifyContent: "space-between",
										alignItems: "center",
										fontSize: "0.82rem",
										padding: "0.35rem 0",
									}}
								>
									<span style={{ color: "hsl(var(--text-tertiary))" }}>
										{label}:
									</span>
									<span style={{ fontWeight: 500 }}>{value}</span>
								</div>
							))}
						</div>

						{/* Description */}
						{selectedReport.description && (
							<div className="card">
								<h4
									style={{
										fontSize: "0.78rem",
										color: "hsl(var(--text-tertiary))",
										textTransform: "uppercase",
										letterSpacing: "0.05em",
										fontWeight: 600,
										marginBottom: "0.375rem",
									}}
								>
									Description
								</h4>
								<p style={{ fontSize: "0.85rem", lineHeight: "1.5" }}>
									{selectedReport.description}
								</p>
							</div>
						)}

						{/* Admin Notes */}
						<div className="form-group" style={{ marginTop: "0.75rem" }}>
							<label className="form-label">Admin Notes</label>
							<textarea
								className="form-control"
								rows={3}
								placeholder="Add notes about this report..."
								value={adminNotes}
								onChange={(e) => setAdminNotes(e.target.value)}
							/>
						</div>

						{/* Status Actions */}
						<div
							style={{
								display: "flex",
								flexDirection: "column",
								gap: "0.5rem",
								marginTop: "0.75rem",
							}}
						>
							{selectedReport.status !== "resolved" && (
								<button
									className="btn btn-success"
									onClick={() =>
										handleStatusUpdate(selectedReport.id, "resolved")
									}
									disabled={actionLoading}
								>
									{actionLoading ? (
										<Loader className="spin" size={14} />
									) : (
										<CheckCircle size={14} />
									)}
									Mark Resolved
								</button>
							)}
							{selectedReport.status !== "reviewed" &&
								selectedReport.status !== "resolved" && (
									<button
										className="btn btn-primary"
										onClick={() =>
											handleStatusUpdate(selectedReport.id, "reviewed")
										}
										disabled={actionLoading}
									>
										{actionLoading ? (
											<Loader className="spin" size={14} />
										) : (
											<Eye size={14} />
										)}
										Mark Reviewed
									</button>
								)}
							{selectedReport.status !== "dismissed" && (
								<button
									className="btn btn-danger"
									onClick={() =>
										handleStatusUpdate(selectedReport.id, "dismissed")
									}
									disabled={actionLoading}
								>
									{actionLoading ? (
										<Loader className="spin" size={14} />
									) : (
										<XCircle size={14} />
									)}
									Dismiss
								</button>
							)}
						</div>
					</div>
				</div>
			)}

			{/* Quick Status Update Dialog */}
			<Dialog
				open={statusUpdate !== null}
				onOpenChange={(open) => {
					if (!open) {
						setStatusUpdate(null);
						setAdminNotes("");
					}
				}}
			>
				<DialogContent>
					<DialogHeader>
						<DialogTitle>Update Report Status</DialogTitle>
					</DialogHeader>
					<div className="form-group">
						<label className="form-label">Notes (optional)</label>
						<textarea
							className="form-control"
							rows={3}
							placeholder="Add any notes..."
							value={adminNotes}
							onChange={(e) => setAdminNotes(e.target.value)}
						/>
					</div>
					<div
						style={{
							display: "flex",
							gap: "0.625rem",
							justifyContent: "flex-end",
							marginTop: "1rem",
						}}
					>
						<DialogClose asChild>
							<button className="btn btn-secondary">Cancel</button>
						</DialogClose>
						<button
							className="btn btn-primary"
							onClick={() =>
								statusUpdate && handleStatusUpdate(statusUpdate.id, statusUpdate.status)
							}
							disabled={actionLoading}
						>
							{actionLoading ? <Loader className="spin" size={14} /> : null}
							Update
						</button>
					</div>
				</DialogContent>
			</Dialog>

		{AlertComponent}
		{ConfirmComponent}
		</div>
	);
};
