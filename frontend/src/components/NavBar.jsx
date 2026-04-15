import { Link, useLocation } from "react-router-dom";


export default function NavBar({ user, onLogout }) {
  const location = useLocation();
  const isAuthPage = location.pathname === "/login" || location.pathname === "/signup";

  return (
    <header className="topbar">
      <div>
        <Link className="brand" to={user ? "/dashboard" : "/login"}>
          Northstar Finance
        </Link>
        <p className="topbar-subtitle">Student MVP for a fintech dashboard</p>
      </div>

      <div className="topbar-actions">
        {user ? (
          <>
            <span className="user-chip">{user.full_name}</span>
            <button className="secondary-button" onClick={onLogout} type="button">
              Log out
            </button>
          </>
        ) : !isAuthPage ? (
          <Link className="secondary-button button-link" to="/login">
            Log in
          </Link>
        ) : null}
      </div>
    </header>
  );
}
