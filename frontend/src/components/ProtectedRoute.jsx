import { Navigate } from "react-router-dom";


export default function ProtectedRoute({ token, authLoading, children }) {
  if (authLoading) {
    return (
      <main className="page-content">
        <div className="panel">
          <p>Loading your dashboard...</p>
        </div>
      </main>
    );
  }

  if (!token) {
    return <Navigate to="/login" replace />;
  }

  return children;
}
