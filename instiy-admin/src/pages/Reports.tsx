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
	ShieldAlert,
	Mail,
	Briefcase,
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
type ReportTab = ReportStatus | "suspended";

const STATUS_TABS: { label: string; value: ReportTab }[] = [
	{ label: "All", value: "" },
	{ label: "Pending", value: "pending" },
	{ label: "Reviewed", value: "reviewed" },
	{ label: "Resolved", value: "resolved" },
	{ label: "Dismissed", value: "dismissed" },
	{ label: "Suspended", value: "suspended" },
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
	misleading_service: "Misleading Service",
	service_scam: "Service Scam / Fraud",
	service_provider_appeal: "Service Provider Appeal",
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
	misleading_service: "hsl(25, 85%, 50%)",
	service_scam: "hsl(30, 90%, 50%)",
	service_provider_appeal: "hsl(35, 95%, 48%)",
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
	const [activeTab, setActiveTab] = useState<ReportTab>("");
	const [selectedReport, setSelectedReport] = useState<any>(null);
	const [actionLoading, setActionLoading] = useState(false);
	const [adminNotes, setAdminNotes] = useState("");
	const [suspendedComplaints, setSuspendedComplaints] = useState<any[]>([]);
	const [suspendedLoading, setSuspendedLoading] = useState(true);
	const [selectedComplaint, setSelectedComplaint] = useState<any>(null);
	const [complaintNotes, setComplaintNotes] = useState("");
	const [complaintActionLoading, setComplaintActionLoading] = useState(false);
	const [statusUpdate, setStatusUpdate] = useState<{
		id: string;
		status: string;
	} | null>(null);
	const [suspendingUserId, setSuspendingUserId] = useState<string | null>(null);
	const { alert, AlertComponent } = useAlert();
	const { confirm, ConfirmComponent } = useConfirm();

	const fetchReports = useCallback(async () => {
		if (activeTab === "suspended") return; // reports table not shown on that tab
		try {
			setLoading(true);
			setFetchError(null);

			const { data, error } = await supabase.rpc("get_admin_reports");
			if (error) throw error;

			const reshaped = (data || []).map((row: any) => ({
				id: row.report_id,
				category: row.category,
				description: row.description,
				evidence_urls: (row.evidence_urls as string[] | null) || [],
				conversation_id: row.conversation_id,
				product_id: row.product_id,
				service_id: row.service_id,
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
				service: row.service_id
					? {
							id: row.service_id,
							title: row.service_title,
							images: row.service_image ? [row.service_image] : [],
							price: row.service_price,
							status: row.service_status,
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

	const fetchSuspendedComplaints = useCallback(async (silent = false) => {
		try {
			if (!silent) setSuspendedLoading(true);

			const { data, error } = await supabase.rpc("get_suspended_complaints");
			if (error) throw error;

			setSuspendedComplaints(
				(data || []).map((row: any) => ({
					id: row.complaint_id,
					text: row.complaint_text,
					status: row.complaint_status,
					admin_notes: row.complaint_admin_notes,
					created_at: row.complaint_created_at,
					user: {
						id: row.user_id,
						full_name: row.user_name,
						email: row.user_email,
						avatar_url: row.user_avatar,
						university: row.user_university,
						joined_at: row.user_joined_at,
						is_seller: row.user_is_seller,
						is_verified: row.user_is_verified,
						suspended_at: row.suspended_at,
					},
					reports_against_count: row.reports_against_count,
					report: row.report_id
						? {
								id: row.report_id,
								category: row.report_category,
								description: row.report_description,
								status: row.report_status,
								reporter_name: row.reporter_name,
							}
						: null,
				})),
			);
		} catch (error) {
			console.error("Error fetching suspended complaints:", error);
		} finally {
			setSuspendedLoading(false);
		}
	}, []);

	useEffect(() => {
		fetchSuspendedComplaints();
	}, [fetchSuspendedComplaints]);

	// Keep the suspended queue fresh when complaints arrive in realtime.
	useEffect(() => {
		const channel = supabase
			.channel("admin-user-complaints")
			.on(
				"postgres_changes",
				{ event: "*", schema: "public", table: "user_complaints" },
				() => {
					fetchSuspendedComplaints(true);
				},
			)
			.subscribe();
		return () => {
			supabase.removeChannel(channel);
		};
	}, [fetchSuspendedComplaints]);

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

			// If resolving a service provider appeal, reinstate provider access and send email
			if (selectedReport?.category === "service_provider_appeal" && newStatus === "resolved") {
				const providerUserId = selectedReport.reporter?.id;
				if (providerUserId) {
					try {
						await supabase.rpc("admin_set_service_provider", {
							p_user_id: providerUserId,
							p_is_service_provider: true,
						});

						const { data: userData } = await supabase
							.from("users")
							.select("email, full_name")
							.eq("id", providerUserId)
							.maybeSingle();

						if (userData?.email) {
							await supabase.functions.invoke("send-email", {
								body: {
									to: userData.email,
									subject: "Your Service Provider Account Has Been Reinstated",
									html: `
										<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08);">
											<div style="background: linear-gradient(135deg, #7c3aed, #9333ea); color: white; padding: 32px 24px; text-align: center;">
												<img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
												<h1 style="margin: 0; font-size: 22px; font-weight: 700; color: white;">Account Reinstated</h1>
											</div>
											<div style="padding: 32px 24px; color: #44403c; line-height: 1.6; font-size: 15px;">
												<p>Hi <strong>${userData.full_name || "there"}</strong>,</p>
												<p>Great news! Your <strong>Instiy Service Provider account</strong> has been reviewed and reinstated by our administrative team.</p>
												<div style="background: #f5f3ff; border: 1px solid #ddd6fe; border-radius: 10px; padding: 14px 16px; margin: 20px 0; color: #5b21b6; font-size: 14px;">
													<strong>You can now access your service dashboard:</strong> Create new service listings, manage packages, and connect with customers on Instiy.
												</div>
												<p>If you had existing listings that were set to inactive, you can visit the <strong>My Services</strong> tab in the app to review and publish them at any time.</p>
												<div style="text-align: center; margin-top: 24px;">
													<a href="https://instiy.com" style="display: block; width: 100%; box-sizing: border-box; background: linear-gradient(135deg, #7c3aed, #6d28d9); color: white !important; text-decoration: none; text-align: center; padding: 14px 24px; border-radius: 12px; font-size: 15px; font-weight: 700;">Open Instiy Services</a>
												</div>
											</div>
											<div style="background: #f5f5f4; padding: 20px; text-align: center; font-size: 12px; color: #78716c; border-top: 1px solid #e7e5e4;">
												<p style="margin: 0;">&copy; ${new Date().getFullYear()} Instiy Support Team</p>
											</div>
										</div>
									`,
								},
							});
						}
					} catch (e) {
						console.error("Failed to auto-reinstate or send email on appeal resolution:", e);
					}
				}
			}

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
			// RPC lifts the suspension, resolves open complaints and
			// notifies the user (their app auto-recovers via realtime).
			const { error } = await supabase.rpc("admin_unsuspend_user", {
				p_user_id: userId,
				p_admin_notes: null,
			});
			if (error) throw error;
			await Promise.all([fetchReports(), fetchSuspendedComplaints(true)]);
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

	// Review actions for the Suspended tab (complaints filed by suspended users).

	const handleComplaintStatusUpdate = async (complaintId: string, status: string) => {
		try {
			setComplaintActionLoading(true);
			const updates: Record<string, any> = {
				status,
				updated_at: new Date().toISOString(),
			};
			const notes = complaintNotes.trim();
			if (notes) updates.admin_notes = notes;

			const { error } = await supabase
				.from("user_complaints")
				.update(updates)
				.eq("id", complaintId);
			if (error) throw error;

			setSelectedComplaint((prev: any) => (prev ? { ...prev, status } : null));
			await fetchSuspendedComplaints(true);
		} catch (error) {
			alert("Error updating complaint", { description: (error as any).message, variant: 'danger' });
		} finally {
			setComplaintActionLoading(false);
		}
	};

	const handleUnsuspendAccount = (complaint: any) => {
		confirm(
			"Unsuspend User",
			async () => {
				try {
					setComplaintActionLoading(true);
					const { error } = await supabase.rpc("admin_unsuspend_user", {
						p_user_id: complaint.user.id,
						p_admin_notes: complaintNotes.trim() || null,
					});
					if (error) throw error;

					setSelectedComplaint(null);
					setComplaintNotes("");
					await Promise.all([fetchSuspendedComplaints(true), fetchReports()]);
					alert("User reinstated", {
						description:
							"The suspension was lifted, their open complaints were marked resolved, and they've been notified.",
					});
				} catch (error) {
					alert("Error unsuspending user", { description: (error as any).message, variant: 'danger' });
				} finally {
					setComplaintActionLoading(false);
				}
			},
			{
				description: `${complaint.user.full_name} will be able to use Instiy again. Their open complaints will be marked resolved and they will receive a reinstatement notification.`,
				confirmLabel: "Unsuspend",
			},
		);
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
							style={
								tab.value === "suspended"
									? { display: "inline-flex", alignItems: "center", gap: 4 }
									: undefined
							}
						>
							{tab.value === "suspended" && <ShieldAlert size={13} />}
							{tab.label}
							{tab.value === "" && (
								<span style={{ marginLeft: 4, opacity: 0.7 }}>
									({filteredCount})
								</span>
							)}
							{tab.value === "suspended" && suspendedComplaints.length > 0 && (
								<span style={{ marginLeft: 4, opacity: 0.7 }}>
									({suspendedComplaints.length})
								</span>
							)}
						</button>
					))}
				</div>
			</div>

			{activeTab === "suspended" ? (
				suspendedLoading && suspendedComplaints.length === 0 ? (
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
				) : suspendedComplaints.length === 0 ? (
					<div className="card" style={{ textAlign: "center", padding: "3rem" }}>
						<ShieldAlert
							size={48}
							style={{
								color: "hsl(var(--text-tertiary))",
								margin: "0 auto 1rem",
							}}
						/>
						<p style={{ color: "hsl(var(--text-tertiary))" }}>
							No suspended user complaints
						</p>
						<p
							style={{
								color: "hsl(var(--text-tertiary))",
								fontSize: "0.85rem",
							}}
						>
							When a suspended user submits a complaint from the app, it will
							appear here for review.
						</p>
					</div>
				) : (
					<div className="table-container">
						<table className="table">
							<thead>
								<tr>
									<th>Suspended User</th>
									<th>Suspended On</th>
									<th>Complaint</th>
									<th>Reports Against</th>
									<th>Submitted</th>
									<th style={{ textAlign: "right" }}>Actions</th>
								</tr>
							</thead>
							<tbody>
								{suspendedComplaints.map((c) => (
									<tr key={c.id}>
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
														c.user?.avatar_url ||
														"https://api.dicebear.com/7.x/bottts/svg?seed=" +
															c.user?.id
													}
													alt={c.user?.full_name}
													style={{
														width: "34px",
														height: "34px",
														borderRadius: "50%",
														border: "1px solid hsl(var(--border))",
														objectFit: "cover",
													}}
												/>
												<div>
													<div
														style={{
															fontWeight: 600,
															fontSize: "0.85rem",
															display: "flex",
															alignItems: "center",
															gap: 6,
														}}
													>
														{c.user?.full_name}
														<span
															className="badge badge-danger"
															style={{
																fontSize: "0.65rem",
																padding: "1px 5px",
															}}
														>
															Suspended
														</span>
													</div>
													<div
														style={{
															fontSize: "0.72rem",
															color: "hsl(var(--text-tertiary))",
														}}
													>
														{c.user?.email}
													</div>
												</div>
											</div>
										</td>
										<td
											style={{
												color: "hsl(var(--text-tertiary))",
												fontSize: "0.8rem",
											}}
										>
											{c.user?.suspended_at
												? new Date(c.user.suspended_at).toLocaleDateString()
												: "—"}
										</td>
										<td style={{ maxWidth: "280px" }}>
											<div
												style={{
													fontSize: "0.82rem",
													overflow: "hidden",
													textOverflow: "ellipsis",
													whiteSpace: "nowrap",
													maxWidth: "260px",
												}}
											>
												{c.text}
											</div>
											<span
												className={`badge ${c.status === "pending" ? "badge-warning" : c.status === "resolved" ? "badge-success" : "badge-secondary"}`}
												style={{ fontSize: "0.68rem", padding: "1px 6px" }}
											>
												{COMPLAINT_STATUS_LABELS[c.status] || c.status}
											</span>
										</td>
										<td
											style={{
												color: "hsl(var(--text-tertiary))",
												fontSize: "0.8rem",
											}}
										>
											{c.reports_against_count}
										</td>
										<td
											style={{
												color: "hsl(var(--text-tertiary))",
												fontSize: "0.8rem",
											}}
										>
											{new Date(c.created_at).toLocaleDateString()}
										</td>
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
														setSelectedComplaint(c);
														setComplaintNotes(c.admin_notes || "");
													}}
												>
													<Eye size={13} /> Review
												</button>
											</div>
										</td>
									</tr>
								))}
							</tbody>
						</table>
					</div>
				)
			) : loading ? (
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
										) : r.service ? (
											<div
												style={{
													display: "flex",
													alignItems: "center",
													gap: "0.5rem",
												}}
											>
												{r.service.images?.[0] ? (
													<img
														src={r.service.images[0]}
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
														<Briefcase
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
														{r.service.title}
													</div>
													{r.service.price != null && (
														<div
															style={{
																fontSize: "0.72rem",
																color: "hsl(var(--text-tertiary))",
															}}
														>
															GH&#162; {formatCurrency(r.service.price)}
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

						{/* Reported Listing (product or service report) */}
						{(selectedReport.product || selectedReport.service) && (
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
									{selectedReport.product && !selectedReport.service ? (
										<>
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
										</>
									) : (
										<>
											{selectedReport.service.images?.[0] ? (
												<img
													src={selectedReport.service.images[0]}
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
													<Briefcase
														size={20}
														style={{ color: "hsl(var(--text-tertiary))" }}
													/>
												</div>
											)}
											<div>
												<div style={{ fontWeight: 600, fontSize: "0.9rem" }}>
													{selectedReport.service.title}
												</div>
												{selectedReport.service.price != null && (
													<div
														style={{
															fontSize: "0.85rem",
															color: "hsl(var(--accent))",
															fontWeight: 600,
														}}
													>
														GH&#162;{" "}
														{formatCurrency(selectedReport.service.price)}
													</div>
												)}
												<a
													href={`/services?id=${selectedReport.service.id}`}
													style={{
														fontSize: "0.75rem",
														color: "hsl(var(--accent))",
														textDecoration: "none",
													}}
												>
													View service &rarr;
												</a>
											</div>
										</>
									)}
								</div>
							</div>
						)}

						{/* Evidence images attached by the reporter */}
						{selectedReport.evidence_urls?.length > 0 && (
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
									Evidence ({selectedReport.evidence_urls.length})
								</h4>
								<div
									style={{
										display: "grid",
										gridTemplateColumns: "repeat(auto-fill, minmax(90px, 1fr))",
										gap: "0.5rem",
									}}
								>
									{selectedReport.evidence_urls.map((url: string, i: number) => (
										<a key={i} href={url} target="_blank" rel="noreferrer">
											<img
												src={url}
												alt={`Evidence ${i + 1}`}
												style={{
													width: "100%",
													height: "72px",
													borderRadius: "6px",
													objectFit: "cover",
													border: "1px solid hsl(var(--border))",
												}}
											/>
										</a>
									))}
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
										: selectedReport.service_id
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
													<Briefcase size={12} /> Service Report
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

			{/* Suspended Complaint Review Drawer */}
			{selectedComplaint && (
				<div
					className="drawer-backdrop"
					onClick={() => setSelectedComplaint(null)}
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
								Suspended Account Review
							</h2>
							<button
								style={{
									background: "none",
									border: "none",
									cursor: "pointer",
									color: "hsl(var(--text-secondary))",
									padding: "4px",
								}}
								onClick={() => setSelectedComplaint(null)}
							>
								<X size={20} />
							</button>
						</div>

						{/* User account under review */}
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
								User Account
							</h4>
							<div
								style={{
									display: "flex",
									alignItems: "center",
									gap: "0.75rem",
									marginBottom: "0.75rem",
								}}
							>
								<img
									src={
										selectedComplaint.user?.avatar_url ||
										"https://api.dicebear.com/7.x/bottts/svg?seed=" +
											selectedComplaint.user?.id
									}
									alt=""
									style={{
										width: "44px",
										height: "44px",
										borderRadius: "50%",
										objectFit: "cover",
									}}
								/>
								<div>
									<div
										style={{
											fontWeight: 600,
											fontSize: "0.9rem",
											display: "flex",
											alignItems: "center",
											gap: 6,
											flexWrap: "wrap",
										}}
									>
										{selectedComplaint.user?.full_name}
										<span
											className="badge badge-danger"
											style={{ fontSize: "0.65rem", padding: "1px 5px" }}
										>
											Suspended
										</span>
										{selectedComplaint.user?.is_seller && (
											<span
												className="badge badge-info"
												style={{ fontSize: "0.65rem", padding: "1px 5px" }}
											>
												Seller
											</span>
										)}
										{selectedComplaint.user?.is_verified && (
											<span
												className="badge badge-success"
												style={{ fontSize: "0.65rem", padding: "1px 5px" }}
											>
												Verified
											</span>
										)}
									</div>
									<div
										style={{
											fontSize: "0.75rem",
											color: "hsl(var(--text-tertiary))",
											display: "flex",
											alignItems: "center",
											gap: 4,
											marginTop: 2,
										}}
									>
										<Mail size={11} />
										{selectedComplaint.user?.email}
									</div>
								</div>
							</div>
							{(
								[
									[
										"University",
										selectedComplaint.user?.university || "—",
									],
									[
										"Joined",
										selectedComplaint.user?.joined_at
											? new Date(
													selectedComplaint.user.joined_at,
												).toLocaleDateString()
											: "—",
									],
									[
										"Suspended on",
										selectedComplaint.user?.suspended_at
											? new Date(
													selectedComplaint.user.suspended_at,
												).toLocaleString()
											: "—",
									],
									[
										"Reports against",
										String(selectedComplaint.reports_against_count ?? 0),
									],
								] as [string, string][]
							).map(([label, value]) => (
								<div
									key={label}
									style={{
										display: "flex",
										justifyContent: "space-between",
										fontSize: "0.8rem",
										padding: "0.25rem 0",
									}}
								>
									<span style={{ color: "hsl(var(--text-tertiary))" }}>
										{label}:
									</span>
									<span style={{ fontWeight: 500 }}>{value}</span>
								</div>
							))}
						</div>

						{/* The complaint that triggered the review */}
						<div
							className="card"
							style={{ borderLeft: "3px solid hsl(var(--danger))" }}
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
								{selectedComplaint.text}
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
									className={`badge ${selectedComplaint.status === "pending" ? "badge-warning" : selectedComplaint.status === "resolved" ? "badge-success" : "badge-secondary"}`}
									style={{ fontSize: "0.68rem", padding: "1px 6px" }}
								>
									{COMPLAINT_STATUS_LABELS[selectedComplaint.status] ||
										selectedComplaint.status}
								</span>
								<span
									style={{
										fontSize: "0.72rem",
										color: "hsl(var(--text-tertiary))",
										marginLeft: "auto",
									}}
								>
									{new Date(selectedComplaint.created_at).toLocaleString()}
								</span>
							</div>
						</div>

						{/* The report that led to the suspension (if any) */}
						{selectedComplaint.report && (
							<div className="card">
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
									Original Report
								</h4>
								<div
									style={{
										display: "flex",
										alignItems: "center",
										gap: "0.5rem",
										marginBottom: "0.5rem",
										flexWrap: "wrap",
									}}
								>
									{getCategoryBadge(selectedComplaint.report.category)}
									{getStatusBadge(selectedComplaint.report.status)}
									{selectedComplaint.report.reporter_name && (
										<span
											style={{
												fontSize: "0.75rem",
												color: "hsl(var(--text-tertiary))",
											}}
										>
											by {selectedComplaint.report.reporter_name}
										</span>
									)}
								</div>
								{selectedComplaint.report.description && (
									<p style={{ fontSize: "0.85rem", lineHeight: "1.5" }}>
										{selectedComplaint.report.description}
									</p>
								)}
							</div>
						)}

						{/* Complaint notes */}
						<div className="form-group" style={{ marginTop: "0.75rem" }}>
							<label className="form-label">Complaint Notes</label>
							<textarea
								className="form-control"
								rows={3}
								placeholder="Notes about this complaint / decision..."
								value={complaintNotes}
								onChange={(e) => setComplaintNotes(e.target.value)}
							/>
						</div>

						{/* Actions */}
						<div
							style={{
								display: "flex",
								flexDirection: "column",
								gap: "0.5rem",
								marginTop: "0.75rem",
							}}
						>
							<button
								className="btn btn-success"
								onClick={() => handleUnsuspendAccount(selectedComplaint)}
								disabled={complaintActionLoading}
							>
								{complaintActionLoading ? (
									<Loader className="spin" size={14} />
								) : (
									<Unlock size={14} />
								)}
								Unsuspend &amp; Resolve
							</button>
							{selectedComplaint.status !== "reviewed" &&
								selectedComplaint.status !== "resolved" && (
									<button
										className="btn btn-primary"
										onClick={() =>
											handleComplaintStatusUpdate(
												selectedComplaint.id,
												"reviewed",
											)
										}
										disabled={complaintActionLoading}
									>
										{complaintActionLoading ? (
											<Loader className="spin" size={14} />
										) : (
											<Eye size={14} />
										)}
										Mark Reviewed (keep suspended)
									</button>
								)}
							{selectedComplaint.status !== "dismissed" &&
								selectedComplaint.status !== "resolved" && (
									<button
										className="btn btn-danger"
										onClick={() =>
											handleComplaintStatusUpdate(
												selectedComplaint.id,
												"dismissed",
											)
										}
										disabled={complaintActionLoading}
									>
										{complaintActionLoading ? (
											<Loader className="spin" size={14} />
										) : (
											<XCircle size={14} />
										)}
										Dismiss Complaint (keep suspended)
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
