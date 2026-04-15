import { Navigate, Route, Routes } from "react-router-dom";
import { useEffect, useState } from "react";

import { apiRequest } from "./api";
import NavBar from "./components/NavBar";
import ProtectedRoute from "./components/ProtectedRoute";
import DashboardPage from "./pages/DashboardPage";
import LoginPage from "./pages/LoginPage";
import SignupPage from "./pages/SignupPage";


const TOKEN_KEY = "fintech_dashboard_token";


export default function App() {
  const [token, setToken] = useState(localStorage.getItem(TOKEN_KEY) || "");
  const [user, setUser] = useState(null);
  const [authLoading, setAuthLoading] = useState(Boolean(localStorage.getItem(TOKEN_KEY)));

  useEffect(() => {
    if (!token) {
      setUser(null);
      setAuthLoading(false);
      return;
    }

    setAuthLoading(true);

    apiRequest("/auth/me", {}, token)
      .then((data) => {
        setUser(data.user);
      })
      .catch(() => {
        clearSession();
      })
      .finally(() => {
        setAuthLoading(false);
      });
  }, [token]);

  function saveSession(sessionToken, sessionUser) {
    localStorage.setItem(TOKEN_KEY, sessionToken);
    setToken(sessionToken);
    setUser(sessionUser);
  }

  function clearSession() {
    localStorage.removeItem(TOKEN_KEY);
    setToken("");
    setUser(null);
  }

  return (
    <div className="app-shell">
      <NavBar user={user} onLogout={clearSession} />
      <Routes>
        <Route
          path="/login"
          element={<LoginPage token={token} onLogin={saveSession} />}
        />
        <Route
          path="/signup"
          element={<SignupPage token={token} onSignup={saveSession} />}
        />
        <Route
          path="/dashboard"
          element={
            <ProtectedRoute token={token} authLoading={authLoading}>
              <DashboardPage user={user} token={token} />
            </ProtectedRoute>
          }
        />
        <Route
          path="*"
          element={<Navigate to={token ? "/dashboard" : "/login"} replace />}
        />
      </Routes>
    </div>
  );
}
