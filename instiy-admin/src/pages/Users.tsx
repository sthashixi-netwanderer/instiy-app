import React, { useEffect, useState } from "react";
import { supabase } from "../supabaseClient";
import {
	Search,
	Shield,
	UserCheck,
	X,
	Eye,
	Loader,
	CreditCard,
	ArrowUpRight,
	ArrowDownLeft,
	Trash2,
	Ban,
	Unlock,
	Pencil,
} from "lucide-react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "../components/dialog";
import { useAlert, useConfirm } from '../components/use-alert';
import { formatCurrency, formatGhs } from "../utils/format";

export const Users: React.FC = () => {
	const [users, setUsers] = useState<any[]>([]);
	const [searchQuery, setSearchQuery] = useState("");
	const [loading, setLoading] = useState(true);
	const [selectedUser, setSelectedUser] = useState<any>(null);
	const [userWallet, setUserWallet] = useState<any>(null);
	const [userTransactions, setUserTransactions] = useState<any[]>([]);
	const [loadingWallet, setLoadingWallet] = useState(false);
	const [listedCount, setListedCount] = useState<number | null>(null);
	const [ordersCount, setOrdersCount] = useState<number | null>(null);
	const [loadingStats, setLoadingStats] = useState(false);
	const [showDeleteModal, setShowDeleteModal] = useState(false);
	const [deleteConfirmName, setDeleteConfirmName] = useState("");
	const [deleting, setDeleting] = useState(false);
	const [currentUserId, setCurrentUserId] = useState<string | null>(null);
	const [editingUser, setEditingUser] = useState(false);
	const [userEdits, setUserEdits] = useState({ full_name: '', email: '', phone_number: '', university: '' });
	const [savingProfile, setSavingProfile] = useState(false);
	const [institutions, setInstitutions] = useState<any[]>([]);
	const [institutionSearch, setInstitutionSearch] = useState('');
	const [showInstitutionDropdown, setShowInstitutionDropdown] = useState(false);
	const [topupAmount, setTopupAmount] = useState('');
	const [topupDescription, setTopupDescription] = useState('');
	const [topupLoading, setTopupLoading] = useState(false);
	const [topupSuccess, setTopupSuccess] = useState(false);
	const { showAlert, AlertComponent } = useAlert();
	const { showConfirm, setConfirmLoading, ConfirmComponent } = useConfirm();

	const fetchUsers = async () => {
		try {
			setLoading(true);
			let query = supabase
				.from("users")
				.select("*")
				.order("created_at", { ascending: false });
			if (searchQuery.trim() !== "") {
				query = query.or(
					`email.ilike.%${searchQuery}%,full_name.ilike.%${searchQuery}%,university.ilike.%${searchQuery}%`,
				);
			}
			const { data, error } = await query;
			if (error) throw error;
			setUsers(data || []);
		} catch (error) {
			console.error("Error fetching users:", error);
		} finally {
			setLoading(false);
		}
	};

	useEffect(() => {
		fetchUsers();
	}, [searchQuery]);

	useEffect(() => {
		supabase.auth.getUser().then(({ data }) => {
			setCurrentUserId(data.user?.id ?? null);
		});
	}, []);

	const openDeleteModal = () => {
		setDeleteConfirmName("");
		setShowDeleteModal(true);
	};

	const deleteUser = async () => {
		if (!selectedUser || deleteConfirmName.trim() !== selectedUser.full_name)
			return;
		setDeleting(true);
		try {
			const { data, error } = await supabase.functions.invoke("delete-user", {
				body: { user_id: selectedUser.id },
			});
			if (error) throw error;
			if (data?.error) throw new Error(data.error);

			setUsers(users.filter((u) => u.id !== selectedUser.id));
			setSelectedUser(null);
			setShowDeleteModal(false);
		} catch (error) {
			showAlert("Error", "Error deleting user: " + (error as any).message, "error");
		} finally {
			setDeleting(false);
		}
	};

	const viewUserDetails = async (user: any) => {
		setSelectedUser(user);
		setLoadingWallet(true);
		setLoadingStats(true);
		setUserWallet(null);
		setUserTransactions([]);
		setListedCount(null);
		setOrdersCount(null);

		try {
			const { data: wallet } = await supabase
				.from("wallets")
				.select("*")
				.eq("user_id", user.id)
				.maybeSingle();

			if (wallet) {
				setUserWallet(wallet);
				const { data: txs } = await supabase
					.from("wallet_transactions")
					.select("*")
					.eq("wallet_id", wallet.id)
					.order("created_at", { ascending: false })
					.limit(10);
				setUserTransactions(txs || []);
			}

			const { count: pCount } = await supabase
				.from("products")
				.select("*", { count: "exact", head: true })
				.eq("seller_id", user.id);
			setListedCount(pCount || 0);

			const { count: oCount } = await supabase
				.from("orders")
				.select("*", { count: "exact", head: true })
				.eq("buyer_id", user.id);
			setOrdersCount(oCount || 0);
		} catch (error) {
			console.error("Error fetching user details:", error);
		} finally {
			setLoadingWallet(false);
			setLoadingStats(false);
		}
	};

	const toggleVerification = async (userId: string, currentStatus: boolean) => {
		const action = currentStatus ? 'revoke verification from' : 'verify';
		showConfirm("Confirm", `Are you sure you want to ${action} this user?`, async () => {
			try {
				const { error } = await supabase
					.from("users")
					.update({ is_verified: !currentStatus })
					.eq("id", userId);
				if (error) throw error;
				setUsers(
					users.map((u) =>
						u.id === userId ? { ...u, is_verified: !currentStatus } : u,
					),
				);
				if (selectedUser?.id === userId)
					setSelectedUser({ ...selectedUser, is_verified: !currentStatus });
			} catch (error) {
				showAlert("Error", "Error updating verification: " + (error as any).message, "error");
			}
		});
	};

	const toggleAdminStatus = async (userId: string, currentStatus: boolean) => {
		const msg = currentStatus
			? "Remove admin privileges from this user?"
			: "Grant admin privileges? They'll have full database access.";
		showConfirm("Confirm", msg, async () => {
			try {
				const { error } = await supabase
					.from("users")
					.update({ is_admin: !currentStatus })
					.eq("id", userId);
				if (error) throw error;
				setUsers(
					users.map((u) =>
						u.id === userId ? { ...u, is_admin: !currentStatus } : u,
					),
				);
				if (selectedUser?.id === userId)
					setSelectedUser({ ...selectedUser, is_admin: !currentStatus });
			} catch (error) {
				showAlert("Error", "Error updating admin status: " + (error as any).message, "error");
			}
		});
	};

	const startEditingUser = async () => {
		if (!selectedUser) return;
		setUserEdits({
			full_name: selectedUser.full_name || '',
			email: selectedUser.email || '',
			phone_number: selectedUser.phone_number || '',
			university: selectedUser.university || '',
		});
		setInstitutionSearch(selectedUser.university || '');
		setEditingUser(true);
		// Load institutions for dropdown
		try {
			const { data } = await supabase.from('institutions').select('*').order('name');
			if (data) setInstitutions(data);
		} catch (_) {}
	};

	const saveUserProfile = async () => {
		if (!selectedUser) return;
		setSavingProfile(true);
		try {
			const { error } = await supabase
				.from('users')
				.update(userEdits)
				.eq('id', selectedUser.id);
			if (error) throw error;

			setSelectedUser({ ...selectedUser, ...userEdits });
			setUsers(users.map(u => u.id === selectedUser.id ? { ...u, ...userEdits } : u));
			setEditingUser(false);

			// In-app notification
			const changes = Object.keys(userEdits)
				.filter((k) => (userEdits as any)[k] !== (selectedUser as any)[k])
				.map((k) => k.replace('_', ' '));
			if (changes.length > 0) {
				await supabase.from('notifications').insert({
					user_id: selectedUser.id,
					title: 'Profile Updated',
					body: `Your profile has been updated by an administrator (${changes.join(', ')}).`,
					type: 'notification',
					data: { fields_updated: changes },
				});
			}

			// Email notification
			try {
				await supabase.functions.invoke('send-email', {
					body: {
						to: selectedUser.email,
						subject: 'Your Instiy Profile Has Been Updated',
						html: `
							<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
								<img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
								<h2 style="color: #7C3AED;">Profile Updated</h2>
								<p>Hi ${userEdits.full_name || selectedUser.full_name},</p>
								<p>An administrator has updated your Instiy profile.</p>
								${changes.length > 0 ? `<p><strong>Changes:</strong> ${changes.join(', ')}</p>` : ''}
								<p>If you did not expect these changes, please contact support.</p>
								<br/>
								<p>Best regards,<br/>The Instiy Team</p>
							</div>
						`,
					},
				});
			} catch (_) { /* email is non-critical */ }
		} catch (error) {
			showAlert("Error", 'Error saving profile: ' + (error as any).message, "error");
		} finally {
			setSavingProfile(false);
		}
	};

	const handleTopup = async () => {
		const amount = parseFloat(topupAmount);
		if (isNaN(amount) || amount <= 0 || !selectedUser) return;

		setTopupLoading(true);
		setTopupSuccess(false);
		try {
			const { error } = await supabase.rpc('admin_topup_wallet', {
				p_user_id: selectedUser.id,
				p_amount: amount,
				p_description: topupDescription || 'Admin balance topup',
			});
			if (error) throw error;

			setTopupAmount('');
			setTopupDescription('');
			setTopupSuccess(true);

			// Email notification
			try {
				await supabase.functions.invoke('send-email', {
					body: {
						to: selectedUser.email,
						subject: 'Your Instiy Wallet Has Been Credited',
						html: `
							<div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
								<img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
								<h2 style="color: #7C3AED;">Balance Topup</h2>
								<p>Hi ${selectedUser.full_name},</p>
								<p>Your Instiy wallet has been credited with <strong>{formatGhs(amount)}</strong> by an administrator.</p>
								${topupDescription ? `<p><strong>Note:</strong> ${topupDescription}</p>` : ''}
								<p>Your new balance is visible in your wallet.</p>
								<br/>
								<p>Best regards,<br/>The Instiy Team</p>
							</div>
						`,
					},
				});
			} catch (_) { /* email is non-critical */ }

			const { data: wallet } = await supabase
				.from('wallets')
				.select('*')
				.eq('user_id', selectedUser.id)
				.maybeSingle();
			if (wallet) {
				setUserWallet(wallet);
				const { data: txs } = await supabase
					.from('wallet_transactions')
					.select('*')
					.eq('wallet_id', wallet.id)
					.order('created_at', { ascending: false })
					.limit(10);
				setUserTransactions(txs || []);
			}

			setTimeout(() => setTopupSuccess(false), 3000);
		} catch (error) {
			showAlert("Error", 'Error topping up wallet: ' + (error as any).message, "error");
		} finally {
			setTopupLoading(false);
		}
	};

	return (
		<div className="animated-fade-in">
			<div className="page-header">
				<div>
					<h1 className="page-title">Users</h1>
					<p
						style={{
							color: "hsl(var(--text-tertiary))",
							marginTop: "0.2rem",
							fontSize: "0.85rem",
						}}
					>
						Manage users, verify sellers, and assign roles
					</p>
				</div>
			</div>

			<div
				className="card"
				style={{ marginBottom: "1.5rem", padding: "0.875rem" }}
			>
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
						placeholder="Search by name, email, or university..."
						value={searchQuery}
						onChange={(e) => setSearchQuery(e.target.value)}
					/>
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
			) : (
				<div className="table-container">
					<table className="table">
						<thead>
							<tr>
								<th>Profile</th>
								<th>University</th>
								<th>Seller Status</th>
								<th>Role</th>
								<th>Joined</th>
								<th style={{ textAlign: "right" }}>Actions</th>
							</tr>
						</thead>
						<tbody>
							{users.length === 0 ? (
								<tr>
									<td
										colSpan={6}
										style={{
											textAlign: "center",
											color: "hsl(var(--text-tertiary))",
											padding: "2rem",
										}}
									>
										No users found
									</td>
								</tr>
							) : (
								users.map((user) => (
									<tr key={user.id}>
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
														user.avatar_url ||
														"https://api.dicebear.com/7.x/bottts/svg?seed=" +
															user.email
													}
													alt={user.full_name}
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
														{user.full_name}
														{user.suspended && (
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
														{user.email}
													</div>
												</div>
											</div>
										</td>
										<td style={{ fontSize: "0.85rem" }}>
											{user.university || "N/A"}
										</td>
										<td>
											<span
												className={`badge ${user.is_verified ? "badge-success" : "badge-warning"}`}
											>
												{user.is_verified ? "Verified" : "Standard"}
											</span>
										</td>
										<td>
											{user.is_admin ? (
												<span
													className="badge badge-danger"
													style={{
														display: "inline-flex",
														gap: "0.25rem",
														alignItems: "center",
													}}
												>
													<Shield size={10} /> Admin
												</span>
											) : (
												<span className="badge badge-info">User</span>
											)}
										</td>
										<td
											style={{
												color: "hsl(var(--text-tertiary))",
												fontSize: "0.8rem",
											}}
										>
											{new Date(user.created_at).toLocaleDateString()}
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
													onClick={() => viewUserDetails(user)}
												>
													<Eye size={13} /> Details
												</button>
												<button
													className={`btn btn-sm ${user.is_verified ? "btn-danger" : "btn-success"}`}
													onClick={() =>
														toggleVerification(user.id, user.is_verified)
													}
												>
													<UserCheck size={13} />{" "}
													{user.is_verified ? "Unverify" : "Verify"}
												</button>
											</div>
										</td>
									</tr>
								))
							)}
						</tbody>
					</table>
				</div>
			)}

			{/* User Details Drawer */}
			{selectedUser && (
				<div className="drawer-backdrop" onClick={() => setSelectedUser(null)}>
					<div className="drawer" onClick={(e) => e.stopPropagation()}>
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
								User Profile
							</h2>
							<button
								style={{
									background: "none",
									border: "none",
									cursor: "pointer",
									color: "hsl(var(--text-secondary))",
									padding: "4px",
								}}
								onClick={() => setSelectedUser(null)}
							>
								<X size={20} />
							</button>
						</div>

						{/* Profile Overview */}
						<div
							style={{
								display: "flex",
								flexDirection: "column",
								alignItems: "center",
								gap: "0.625rem",
								padding: "0.75rem 0",
							}}
						>
							<img
								src={
									selectedUser.avatar_url ||
									"https://api.dicebear.com/7.x/bottts/svg?seed=" +
										selectedUser.email
								}
								alt={selectedUser.full_name}
								style={{
									width: "72px",
									height: "72px",
									borderRadius: "50%",
									border: "2px solid hsl(var(--accent))",
									objectFit: "cover",
								}}
							/>
							<h3 style={{ fontSize: "1.1rem" }}>{selectedUser.full_name}</h3>
							{selectedUser.suspended && (
								<span
									className="badge badge-danger"
									style={{ fontSize: "0.7rem", padding: "2px 8px" }}
								>
									Suspended
								</span>
							)}
							<p
								style={{
									color: "hsl(var(--text-tertiary))",
									fontSize: "0.8rem",
								}}
							>
								{selectedUser.email}
							</p>
						</div>

						{/* Details */}
						<div
							className="card"
							style={{
								display: "flex",
								flexDirection: "column",
								gap: "0.625rem",
								background: "hsl(var(--bg-surface))",
							}}
						>
							<div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
								<span style={{ fontSize: "0.9rem", fontWeight: 600 }}>Details</span>
								{!editingUser ? (
									<button
										className="btn btn-secondary btn-sm"
										onClick={startEditingUser}
									>
										<Pencil size={13} /> Edit
									</button>
								) : (
									<div style={{ display: "flex", gap: "4px" }}>
										<button
											className="btn btn-primary btn-sm"
											onClick={saveUserProfile}
											disabled={savingProfile}
										>
											{savingProfile ? <Loader size={13} className="spin" /> : "Save"}
										</button>
										<button
											className="btn btn-secondary btn-sm"
											onClick={() => setEditingUser(false)}
										>
											Cancel
										</button>
									</div>
								)}
							</div>

							{editingUser ? (
								<div style={{ display: "flex", flexDirection: "column", gap: "0.5rem" }}>
									{[
										{ key: "full_name", label: "Full Name", type: "text" },
										{ key: "email", label: "Email", type: "email" },
										{ key: "phone_number", label: "Phone", type: "text" },
									].map(({ key, label, type }) => (
										<div key={key}>
											<label style={{ fontSize: "0.72rem", color: "hsl(var(--text-tertiary))", display: "block", marginBottom: "2px" }}>{label}</label>
											<input
												type={type}
												value={(userEdits as any)[key] || ""}
												onChange={(e) => setUserEdits({ ...userEdits, [key]: e.target.value })}
												className="form-control"
											/>
										</div>
									))}

									{/* Institution searchable dropdown */}
									<div style={{ position: "relative" }}>
										<label style={{ fontSize: "0.72rem", color: "hsl(var(--text-tertiary))", display: "block", marginBottom: "2px" }}>University</label>
										<input
											type="text"
											placeholder="Search institution..."
											value={institutionSearch}
											onChange={(e) => {
												setInstitutionSearch(e.target.value);
												setShowInstitutionDropdown(true);
												setUserEdits({ ...userEdits, university: e.target.value });
											}}
											onFocus={() => setShowInstitutionDropdown(true)}
											className="form-control"
										/>
										{showInstitutionDropdown && (
											<div
												style={{
													position: "absolute",
													top: "100%",
													left: 0,
													right: 0,
													background: "hsl(var(--bg-surface))",
													border: "1px solid hsl(var(--border))",
													borderRadius: "6px",
													maxHeight: "150px",
													overflowY: "auto",
													zIndex: 100,
													marginTop: "2px",
													boxShadow: "0 4px 12px rgba(0,0,0,0.1)",
												}}
											>
												{institutions
													.filter((i) =>
														i.name.toLowerCase().includes(institutionSearch.toLowerCase())
													)
													.map((inst) => (
														<div
															key={inst.id}
															onClick={() => {
																setUserEdits({ ...userEdits, university: inst.name });
																setInstitutionSearch(inst.name);
																setShowInstitutionDropdown(false);
															}}
															style={{
																padding: "6px 8px",
																cursor: "pointer",
																fontSize: "0.82rem",
																borderBottom: "1px solid hsl(var(--border))",
																display: "flex",
																alignItems: "center",
																gap: "8px",
															}}
															onMouseEnter={(e) => (e.currentTarget.style.background = "hsl(var(--bg))")}
															onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
														>
															{inst.logo_url && (
																<img
																	src={inst.logo_url}
																	alt=""
																	style={{ width: "20px", height: "20px", borderRadius: "50%", objectFit: "cover" }}
																/>
															)}
															<span>{inst.name}</span>
														</div>
													))
													.slice(0, 10)}
												{institutions.filter((i) =>
													i.name.toLowerCase().includes(institutionSearch.toLowerCase())
												).length === 0 && (
													<div style={{ padding: "8px", fontSize: "0.78rem", color: "hsl(var(--text-tertiary))", textAlign: "center" }}>
														No institutions found
													</div>
												)}
												<div
													onClick={() => setShowInstitutionDropdown(false)}
													style={{ padding: "6px 8px", fontSize: "0.72rem", color: "hsl(var(--text-tertiary))", textAlign: "center", cursor: "pointer" }}
												>
													Close
												</div>
											</div>
										)}
									</div>
								</div>
							) : (
								<>
									{[
										["University", selectedUser.university || "N/A"],
										["Phone", selectedUser.phone_number || "N/A"],
										["Joined", new Date(selectedUser.created_at).toLocaleString()],
									].map(([label, value]) => (
										<div
											key={label}
											style={{
												display: "flex",
												justifyContent: "space-between",
												fontSize: "0.82rem",
											}}
										>
											<span style={{ color: "hsl(var(--text-tertiary))" }}>
												{label}:
											</span>
											<span>{value}</span>
										</div>
									))}
								</>
							)}
							<div
								style={{
									borderTop: "1px solid hsl(var(--border))",
									paddingTop: "0.5rem",
									marginTop: "0.25rem",
									display: "flex",
									justifyContent: "space-between",
									fontSize: "0.82rem",
								}}
							>
								<span style={{ color: "hsl(var(--text-tertiary))" }}>
									Listed:
								</span>
								<span>{loadingStats ? "..." : listedCount}</span>
							</div>
							<div
								style={{
									display: "flex",
									justifyContent: "space-between",
									fontSize: "0.82rem",
								}}
							>
								<span style={{ color: "hsl(var(--text-tertiary))" }}>
									Orders:
								</span>
								<span>{loadingStats ? "..." : ordersCount}</span>
							</div>
							{selectedUser.bio && (
								<div
									style={{
										borderTop: "1px solid hsl(var(--border))",
										paddingTop: "0.625rem",
										marginTop: "0.25rem",
									}}
								>
									<span
										style={{
											color: "hsl(var(--text-tertiary))",
											fontSize: "0.78rem",
											display: "block",
											marginBottom: "0.25rem",
										}}
									>
										Bio
									</span>
									<p style={{ fontSize: "0.82rem", lineHeight: 1.5 }}>
										{selectedUser.bio}
									</p>
								</div>
							)}
						</div>

						{/* Wallet */}
						<div
							className="card"
							style={{
								display: "flex",
								flexDirection: "column",
								gap: "0.625rem",
							}}
						>
							<h4
								style={{
									display: "flex",
									alignItems: "center",
									gap: "0.5rem",
									fontSize: "0.9rem",
									color: "hsl(var(--text-secondary))",
									fontWeight: 600,
								}}
							>
								<CreditCard size={16} /> Seller Wallet
							</h4>
							{loadingWallet ? (
								<div
									style={{
										display: "flex",
										justifyContent: "center",
										padding: "1rem",
									}}
								>
									<Loader
										className="spin"
										size={18}
										style={{ color: "hsl(var(--accent))" }}
									/>
								</div>
							) : userWallet ? (
								<div>
									<div
										style={{
											fontSize: "1.5rem",
											fontWeight: 700,
											fontFamily: "var(--font-title)",
											margin: "0.25rem 0",
										}}
									>
										{formatGhs(userWallet.balance)}
									</div>
									<div
										style={{
											display: "flex",
											justifyContent: "space-between",
											fontSize: "0.75rem",
											color: "hsl(var(--text-tertiary))",
										}}
									>
										<span>
											Pending: GH₵
											{formatCurrency(userWallet.pending_balance || 0)}
										</span>
										<span>
											Updated:{" "}
											{new Date(userWallet.updated_at).toLocaleDateString()}
										</span>
									</div>

									{/* Admin Topup */}
									<div
										style={{
											marginTop: "1rem",
											padding: "0.75rem",
											borderRadius: "8px",
											border: "1px dashed hsl(var(--border))",
											display: "flex",
											flexDirection: "column",
											gap: "0.5rem",
										}}
									>
										<span style={{ fontSize: "0.78rem", color: "hsl(var(--text-tertiary))", textTransform: "uppercase", letterSpacing: "0.05em" }}>
											Admin Topup
										</span>
										<input
											type="number"
											placeholder="Amount (GH₵)"
											value={topupAmount}
											onChange={(e) => setTopupAmount(e.target.value)}
											min="0"
											step="0.01"
											className="form-control"
										/>
										<input
											type="text"
											placeholder="Description (optional)"
											value={topupDescription}
											onChange={(e) => setTopupDescription(e.target.value)}
											className="form-control"
										/>
										<button
											className="btn btn-primary"
											style={{ fontSize: "0.78rem" }}
											onClick={handleTopup}
											disabled={topupLoading || !topupAmount || parseFloat(topupAmount) <= 0}
										>
											{topupLoading ? <Loader size={14} className="spin" /> : <CreditCard size={14} />}
											{topupLoading ? " Processing..." : " Top Up Wallet"}
										</button>
										{topupSuccess && (
											<span style={{ fontSize: "0.75rem", color: "hsl(142 71% 45%)", fontWeight: 500 }}>
												✓ Wallet topped up successfully
											</span>
										)}
									</div>

									<div style={{ marginTop: "1rem" }}>
										<h5
											style={{
												fontSize: "0.78rem",
												color: "hsl(var(--text-tertiary))",
												marginBottom: "0.5rem",
												textTransform: "uppercase",
												letterSpacing: "0.05em",
											}}
										>
											Recent Transactions
										</h5>
										{userTransactions.length === 0 ? (
											<p
												style={{
													fontSize: "0.78rem",
													color: "hsl(var(--text-tertiary))",
													textAlign: "center",
													padding: "0.5rem",
												}}
											>
												No transactions
											</p>
										) : (
											<div
												style={{
													display: "flex",
													flexDirection: "column",
													gap: "0.375rem",
													maxHeight: "160px",
													overflowY: "auto",
												}}
											>
												{userTransactions.map((tx) => {
													const isIncoming = [
														"deposit",
														"transfer_in",
														"refund",
													].includes(tx.type);
													return (
														<div
															key={tx.id}
															style={{
																display: "flex",
																justifyContent: "space-between",
																padding: "0.5rem",
																background: "hsl(var(--bg-surface))",
																borderRadius: "4px",
																fontSize: "0.78rem",
															}}
														>
															<div
																style={{
																	display: "flex",
																	alignItems: "center",
																	gap: "0.5rem",
																}}
															>
																{isIncoming ? (
																	<ArrowDownLeft
																		size={13}
																		style={{
																			color: "hsl(var(--success-hover))",
																		}}
																	/>
																) : (
																	<ArrowUpRight
																		size={13}
																		style={{
																			color: "hsl(var(--danger-hover))",
																		}}
																	/>
																)}
																<div>
																	<div
																		style={{
																			fontWeight: 600,
																			textTransform: "capitalize",
																		}}
																	>
																		{tx.type.replace("_", " ")}
																	</div>
																	<div
																		style={{
																			fontSize: "0.68rem",
																			color: "hsl(var(--text-tertiary))",
																		}}
																	>
																		{tx.description || tx.reference || ""}
																	</div>
																</div>
															</div>
															<div
																style={{
																	fontWeight: 700,
																	color: isIncoming
																		? "hsl(var(--success-hover))"
																		: "hsl(var(--danger-hover))",
																}}
															>
																{isIncoming ? "+" : "-"}GH₵
																{formatCurrency(tx.amount)}
															</div>
														</div>
													);
												})}
											</div>
										)}
									</div>
								</div>
							) : (
								<p
									style={{
										fontSize: "0.82rem",
										color: "hsl(var(--text-tertiary))",
										textAlign: "center",
										padding: "0.75rem",
									}}
								>
									No wallet found
								</p>
							)}
						</div>

						{/* Actions */}
						<div
							style={{
								display: "flex",
								flexDirection: "column",
								gap: "0.625rem",
								marginTop: "auto",
							}}
						>
							<h4
								style={{
									fontSize: "0.78rem",
									color: "hsl(var(--text-tertiary))",
									textTransform: "uppercase",
									letterSpacing: "0.05em",
									fontWeight: 600,
								}}
							>
								Admin Controls
							</h4>
							<div
								style={{
									display: "grid",
									gridTemplateColumns: "1fr 1fr",
									gap: "0.625rem",
								}}
							>
								<button
									className={`btn ${selectedUser.is_verified ? "btn-danger" : "btn-success"}`}
									onClick={() =>
										toggleVerification(
											selectedUser.id,
											selectedUser.is_verified,
										)
									}
								>
									{selectedUser.is_verified
										? "Revoke Verification"
										: "Verify Seller"}
								</button>
								<button
									className={`btn ${selectedUser.is_admin ? "btn-secondary" : "btn-danger"}`}
									style={
										selectedUser.is_admin
											? {
													border: "1px solid hsl(var(--danger) / 0.4)",
													color: "hsl(var(--danger-hover))",
												}
											: {}
									}
									onClick={() =>
										toggleAdminStatus(selectedUser.id, selectedUser.is_admin)
									}
								>
									{selectedUser.is_admin ? "Remove Admin" : "Grant Admin"}
								</button>
							</div>
							{selectedUser.suspended ? (
								<button
									className="btn btn-success"
									style={{
										marginTop: "0.25rem",
										display: "flex",
										alignItems: "center",
										justifyContent: "center",
										gap: "0.5rem",
									}}
									onClick={async () => {
										// RPC lifts the suspension, resolves open
										// complaints and notifies the user.
										const { error } = await supabase.rpc(
											"admin_unsuspend_user",
											{ p_user_id: selectedUser.id, p_admin_notes: null },
										);
										if (error) {
											showAlert("Error", "Error: " + error.message, "error");
											return;
										}
										setSelectedUser({
											...selectedUser,
											suspended: false,
											suspended_at: null,
										});
										setUsers(
											users.map((u) =>
												u.id === selectedUser.id
													? { ...u, suspended: false, suspended_at: null }
													: u,
											),
										);
									}}
								>
									<Unlock size={14} /> Unsuspend User
								</button>
							) : (
								<button
									className="btn btn-danger"
									style={{
										marginTop: "0.25rem",
										display: "flex",
										alignItems: "center",
										justifyContent: "center",
										gap: "0.5rem",
									}}
									onClick={() => {
										showConfirm("Confirm", "Suspend this user? They will be automatically logged out and unable to log back in.", async () => {
											setConfirmLoading(true);
											try {
												const { error } = await supabase
													.from("users")
													.update({
														suspended: true,
														suspended_at: new Date().toISOString(),
													})
													.eq("id", selectedUser.id);
												if (error) {
													showAlert("Error", "Error: " + error.message, "error");
													return;
												}
												setSelectedUser({
													...selectedUser,
													suspended: true,
													suspended_at: new Date().toISOString(),
												});
												setUsers(
													users.map((u) =>
														u.id === selectedUser.id
															? { ...u, suspended: true }
															: u,
													),
												);
											} finally {
												setConfirmLoading(false);
											}
										});
									}}
								>
									<Ban size={14} /> Suspend User
								</button>
							)}
							<button
								className="btn btn-danger"
								style={{
									marginTop: "0.25rem",
									display: "flex",
									alignItems: "center",
									justifyContent: "center",
									gap: "0.5rem",
								}}
								onClick={openDeleteModal}
								disabled={selectedUser.id === currentUserId}
								title={
									selectedUser.id === currentUserId
										? "Cannot delete your own account"
										: "Permanently delete this user"
								}
							>
								<Trash2 size={14} /> Delete User Account
							</button>
						</div>
					</div>
				</div>
			)}

			{/* Delete Confirmation Modal */}
			<Dialog open={showDeleteModal && !!selectedUser} onOpenChange={(open) => { if (!open) { setShowDeleteModal(false); setDeleteConfirmName(""); } }}>
				<DialogContent style={{ maxWidth: "420px" }}>
					<DialogHeader>
						<DialogTitle style={{ color: "hsl(var(--danger-hover))" }}>
							Delete User Account
						</DialogTitle>
					</DialogHeader>
					<p
						style={{
							fontSize: "0.85rem",
							color: "hsl(var(--text-secondary))",
							marginBottom: "0.75rem",
						}}
					>
						This will permanently delete{" "}
						<strong>{selectedUser?.full_name}</strong>'s account and all
						associated data (products, orders, wallet, messages). This action
						cannot be undone.
					</p>
					<p
						style={{
							fontSize: "0.82rem",
							color: "hsl(var(--text-tertiary))",
							marginBottom: "0.75rem",
						}}
					>
						Type <strong>{selectedUser?.full_name}</strong> to confirm:
					</p>
					<input
						type="text"
						className="form-control"
						value={deleteConfirmName}
						onChange={(e) => setDeleteConfirmName(e.target.value)}
						placeholder="Enter full name"
						style={{ marginBottom: "1rem" }}
						autoFocus
					/>
					<div
						style={{
							display: "flex",
							gap: "0.625rem",
							justifyContent: "flex-end",
						}}
					>
						<button
							className="btn btn-secondary"
							onClick={() => { setShowDeleteModal(false); setDeleteConfirmName(""); }}
						>
							Cancel
						</button>
						<button
							className="btn btn-danger"
							onClick={deleteUser}
							disabled={
								deleteConfirmName.trim() !== selectedUser?.full_name ||
								deleting
							}
						>
							{deleting ? "Deleting..." : "Delete Account"}
						</button>
					</div>
				</DialogContent>
			</Dialog>
		{AlertComponent}
		{ConfirmComponent}
	</div>
	);
};
