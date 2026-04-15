import { Link, Navigate, useNavigate } from "react-router-dom";
import { useState } from "react";

import { apiRequest } from "../api";


export default function SignupPage({ token, onSignup }) {
  const navigate = useNavigate();
  const [form, setForm] = useState({
    full_name: "",
    email: "",
    password: "",
  });
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  if (token) {
    return <Navigate to="/dashboard" replace />;
  }

  function handleChange(event) {
    const { name, value } = event.target;
    setForm((currentForm) => ({
      ...currentForm,
      [name]: value,
    }));
  }

  async function handleSubmit(event) {
    event.preventDefault();
    setSubmitting(true);
    setError("");

    try {
      const data = await apiRequest("/auth/signup", {
        method: "POST",
        body: JSON.stringify(form),
      });

      onSignup(data.token, data.user);
      navigate("/dashboard");
    } catch (requestError) {
      setError(requestError.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="page-content auth-layout">
      <section className="panel auth-panel">
        <div className="panel-header">
          <div>
            <h1>Create your account</h1>
            <p>Start with a minimal account flow for the project MVP.</p>
          </div>
        </div>

        <form className="form-grid" onSubmit={handleSubmit}>
          <label>
            Full name
            <input
              name="full_name"
              onChange={handleChange}
              placeholder="Jordan Lee"
              required
              value={form.full_name}
            />
          </label>

          <label>
            Email
            <input
              name="email"
              onChange={handleChange}
              placeholder="student@example.com"
              required
              type="email"
              value={form.email}
            />
          </label>

          <label>
            Password
            <input
              name="password"
              onChange={handleChange}
              required
              type="password"
              value={form.password}
            />
          </label>

          {error ? <p className="form-error">{error}</p> : null}

          <button className="primary-button" disabled={submitting} type="submit">
            {submitting ? "Creating account..." : "Sign up"}
          </button>
        </form>

        <p className="auth-footer">
          Already registered? <Link to="/login">Log in</Link>
        </p>
      </section>
    </main>
  );
}
