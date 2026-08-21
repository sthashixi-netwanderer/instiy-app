import React, { useEffect, useState } from "react";
import { supabase } from "./supabaseClient";
import { Login } from "./pages/Login";
import { Dashboard } from "./pages/Dashboard";
import { Users } from "./pages/Users";
import { Categories } from "./pages/Categories";
import { Products } from "./pages/Products";
import { Orders } from "./pages/Orders";
import { Withdrawals } from "./pages/Withdrawals";
import { Institutions } from "./pages/Institutions";
import { Verifications } from "./pages/Verifications";
import { Policies } from "./pages/Policies";
import { CuratedCollections } from "./pages/CuratedCollections";
import { Reports } from "./pages/Reports";
import { Carousel } from "./pages/Carousel";
import { AISettings } from "./pages/AISettings";
import { GPSConfig } from "./pages/GPSConfig";
import { WithdrawalFees } from "./pages/WithdrawalFees";
import { Transactions } from "./pages/Transactions";

import { Routes, Route, Navigate, useLocation, Link } from "react-router-dom";

import {
	Shield,
	LayoutDashboard,
	Users as UsersIcon,
	FolderTree,
	ShoppingBag,
	Receipt,
	Landmark,
	LogOut,
	Menu,
	X,
	User,
	School,
	FileText,
	LayoutGrid,
	Flag,
	Images,
	BrainCircuit,
	MapPin,
	Wallet,
} from "lucide-react";
const instiyLogo = "/favicon.svg";

export const App: React.FC = () => {
	const [sessionUser, setSessionUser] = useState<string | null>(null);
	const [adminEmail, setAdminEmail] = useState<string>("");
	const [sidebarOpen, setSidebarOpen] = useState(false);
	const [authLoading, setAuthLoading] = useState(true);
	const [unreadReports, setUnreadReports] = useState(0);
	const [pendingVerifications, setPendingVerifications] = useState(0);
	const location = useLocation();

	// Fetch unread report count
	const fetchUnreadCount = async () => {
		try {
			const { data, error } = await supabase.rpc("get_unread_report_count");
			if (!error && data != null) {
				setUnreadReports(data as number);
			}
		} catch (_) {}
	};

	// Fetch pending verification count
	const fetchPendingVerificationCount = async () => {
		try {
			const { data, error } = await supabase.rpc("get_unread_verification_count");
			if (!error && data != null) {
				setPendingVerifications(data as number);
			}
		} catch (_) {}
	};

	useEffect(() => {
		if (sessionUser) {
			fetchUnreadCount();
			fetchPendingVerificationCount();
			const interval = setInterval(() => {
				fetchUnreadCount();
				fetchPendingVerificationCount();
			}, 30000);
			return () => clearInterval(interval);
		}
	}, [sessionUser]);

	useEffect(() => {
		supabase.auth.getSession().then(({ data: { session } }) => {
			if (session?.user) {
				verifyAdmin(session.user.id, session.user.email || "");
			} else {
				setAuthLoading(false);
			}
		});

		const {
			data: { subscription },
		} = supabase.auth.onAuthStateChange((_event, session) => {
			if (session?.user) {
				verifyAdmin(session.user.id, session.user.email || "");
			} else {
				setSessionUser(null);
				setAdminEmail("");
				setAuthLoading(false);
			}
		});

		return () => subscription.unsubscribe();
	}, []);

	const verifyAdmin = async (userId: string, email: string) => {
		try {
			const { data: profile, error } = await supabase
				.from("users")
				.select("is_admin")
				.eq("id", userId)
				.single();

			if (error || !profile?.is_admin) {
				await supabase.auth.signOut();
				setSessionUser(null);
				setAdminEmail("");
			} else {
				setSessionUser(userId);
				setAdminEmail(email);
			}
		} catch (e) {
			console.error(e);
			setSessionUser(null);
		} finally {
			setAuthLoading(false);
		}
	};

	const handleLogout = async () => {
		await supabase.auth.signOut();
		setSessionUser(null);
		setAdminEmail("");
	};

	if (authLoading) {
		return (
			<div
				style={{
					display: "flex",
					alignItems: "center",
					justifyContent: "center",
					minHeight: "100vh",
					backgroundColor: "hsl(var(--bg-main))",
				}}
			>
				<div
					style={{
						display: "flex",
						flexDirection: "column",
						alignItems: "center",
						gap: "0.75rem",
					}}
				>
					<Shield
						size={36}
						className="spin"
						style={{ color: "hsl(var(--accent))" }}
					/>
					<p
						style={{ color: "hsl(var(--text-tertiary))", fontSize: "0.85rem" }}
					>
						Verifying access...
					</p>
				</div>
			</div>
		);
	}

	if (!sessionUser) {
		return <Login onLoginSuccess={(uid) => setSessionUser(uid)} />;
	}

	interface NavItem {
		id: string;
		label: string;
		icon: React.ReactNode;
		path: string;
		badgeCount?: number;
	}

	const navItems: NavItem[] = [
		{
			id: "dashboard",
			label: "Dashboard",
			icon: <LayoutDashboard size={18} />,
			path: "/dashboard",
		},
		{
			id: "users",
			label: "Users & Sellers",
			icon: <UsersIcon size={18} />,
			path: "/users",
		},
		{
			id: "verifications",
			label: "Verifications",
			icon: <Shield size={18} />,
			path: "/verifications",
			badgeCount: pendingVerifications,
		},
		{
			id: "categories",
			label: "Categories",
			icon: <FolderTree size={18} />,
			path: "/categories",
		},
		{
			id: "products",
			label: "Products",
			icon: <ShoppingBag size={18} />,
			path: "/products",
		},
		{
			id: "orders",
			label: "Orders",
			icon: <Receipt size={18} />,
			path: "/orders",
		},
		{
			id: "withdrawals",
			label: "Cashouts",
			icon: <Landmark size={18} />,
			path: "/withdrawals",
		},
		{
			id: "transactions",
			label: "Transactions",
			icon: <Wallet size={18} />,
			path: "/transactions",
		},
		{
			id: "institutions",
			label: "Institutions",
			icon: <School size={18} />,
			path: "/institutions",
		},
		{
			id: "policies",
			label: "Policies",
			icon: <FileText size={18} />,
			path: "/policies",
		},
		{
			id: "curated",
			label: "Curated Collections",
			icon: <LayoutGrid size={18} />,
			path: "/curated",
		},
		{
			id: "carousel",
			label: "Home Carousel",
			icon: <Images size={18} />,
			path: "/carousel",
		},
		{
			id: "reports",
			label: "Reports",
			icon: <Flag size={18} />,
			path: "/reports",
			badgeCount: unreadReports,
		},
		{
			id: "ai-settings",
			label: "AI Settings",
			icon: <BrainCircuit size={18} />,
			path: "/ai-settings",
		},
		{
			id: "gps-settings",
			label: "GPS Settings",
			icon: <MapPin size={18} />,
			path: "/gps-settings",
		},
	];

	return (
		<div className="app-container">
			{/* Mobile Top Navbar */}
			<header
				id="mobile-header"
				style={{
					display: "none",
					position: "fixed",
					top: 0,
					left: 0,
					right: 0,
					height: "56px",
					padding: "0 1.25rem",
					alignItems: "center",
					justifyContent: "space-between",
					zIndex: 99,
					backgroundColor: "hsl(var(--bg-sidebar))",
					borderBottom: "1px solid hsl(var(--border))",
				}}
			>
				<div
					style={{
						display: "flex",
						alignItems: "center",
						gap: "0.5rem",
						fontSize: "1.15rem",
						fontWeight: 700,
						fontFamily: "var(--font-title)",
					}}
				>
					<img src={instiyLogo} alt="Instiy" style={{ width: "20px", height: "20px" }} />
					Instiy
				</div>
				<button
					style={{
						background: "none",
						border: "none",
						color: "hsl(var(--text-main))",
						cursor: "pointer",
						padding: "4px",
					}}
					onClick={() => setSidebarOpen(!sidebarOpen)}
				>
					{sidebarOpen ? <X size={22} /> : <Menu size={22} />}
				</button>
			</header>

			{/* Sidebar */}
			<aside className={`sidebar ${sidebarOpen ? "open" : ""}`}>
				<div className="sidebar-logo">
					<img src={instiyLogo} alt="Instiy" style={{ width: "24px", height: "24px" }} />
					<span>Instiy</span>
				</div>

				<ul className="sidebar-menu">
					{navItems.map((item) => {
						const isActive =
							location.pathname === item.path ||
							(item.path === "/dashboard" && location.pathname === "/");
						const badgeCount = (item as any).badgeCount || 0;
						const showBadge = badgeCount > 0;
						return (
							<li
								key={item.id}
								className={`sidebar-item ${isActive ? "active" : ""}`}
								onClick={() => setSidebarOpen(false)}
							>
								<Link to={item.path}>
									{item.icon}
									<span>{item.label}</span>
									{showBadge && (
										<span
											style={{
												marginLeft: "auto",
												display: "inline-flex",
												alignItems: "center",
												justifyContent: "center",
												background: "hsl(var(--accent))",
												color: "white",
												borderRadius: "10px",
												minWidth: "18px",
												height: "18px",
												padding: "0 5px",
												fontSize: "0.65rem",
												fontWeight: 700,
											}}
										>
											{badgeCount > 99 ? '99+' : badgeCount}
										</span>
									)}
								</Link>
							</li>
						);
					})}
				</ul>

				<div className="sidebar-footer">
					<div
						style={{
							display: "flex",
							alignItems: "center",
							gap: "0.625rem",
							marginBottom: "0.875rem",
						}}
					>
						<div
							style={{
								width: "32px",
								height: "32px",
								borderRadius: "50%",
								background: "hsl(var(--accent-dim))",
								display: "flex",
								alignItems: "center",
								justifyContent: "center",
								color: "hsl(var(--accent))",
							}}
						>
							<User size={14} />
						</div>
						<div style={{ overflow: "hidden", flex: 1, minWidth: 0 }}>
							<div style={{ fontSize: "0.8rem", fontWeight: 600 }}>Admin</div>
							<div
								style={{
									fontSize: "0.7rem",
									color: "hsl(var(--text-tertiary))",
									whiteSpace: "nowrap",
									overflow: "hidden",
									textOverflow: "ellipsis",
								}}
								title={adminEmail}
							>
								{adminEmail}
							</div>
						</div>
					</div>
					<button
						className="btn btn-secondary"
						style={{
							width: "100%",
							padding: "0.45rem",
							display: "flex",
							alignItems: "center",
							justifyContent: "center",
							gap: "0.5rem",
							fontSize: "0.8rem",
						}}
						onClick={handleLogout}
					>
						<LogOut size={14} /> Logout
					</button>
				</div>
			</aside>

			{/* Main Content */}
			<main className="main-content" id="main-content-layout">
				<Routes>
					<Route path="/" element={<Navigate to="/dashboard" replace />} />
					<Route path="/dashboard" element={<Dashboard />} />
					<Route path="/users" element={<Users />} />
					<Route path="/verifications" element={<Verifications />} />
					<Route path="/categories" element={<Categories />} />
					<Route path="/products" element={<Products />} />
					<Route path="/orders" element={<Orders />} />
					<Route path="/withdrawals" element={<Withdrawals />} />
					<Route path="/transactions" element={<Transactions />} />
					<Route path="/institutions" element={<Institutions />} />
					<Route path="/policies" element={<Policies />} />
					<Route path="/curated" element={<CuratedCollections />} />
					<Route path="/carousel" element={<Carousel />} />
					<Route path="/reports" element={<Reports />} />
					<Route path="/ai-settings" element={<AISettings />} />
					<Route path="/gps-settings" element={<GPSConfig />} />
					<Route path="/withdrawal-fees" element={<WithdrawalFees />} />
					<Route path="*" element={<Navigate to="/dashboard" replace />} />
				</Routes>
			</main>
		</div>
	);
};

export default App;
