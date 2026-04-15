import { useState } from "react";

import { apiRequest } from "../api";


const INITIAL_FORM = {
  recipient_name: "",
  amount: "",
  transaction_type: "payment",
  reference: "",
};


export default function TransactionForm({ token, onTransactionCreated }) {
  const [form, setForm] = useState(INITIAL_FORM);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

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
      const data = await apiRequest(
        "/transactions",
        {
          method: "POST",
          body: JSON.stringify(form),
        },
        token
      );

      onTransactionCreated(data.transaction);
      setForm(INITIAL_FORM);
    } catch (requestError) {
      setError(requestError.message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <section className="panel">
      <div className="panel-header">
        <div>
          <h2>Submit a payment</h2>
          <p>Create a simple transaction record for the dashboard.</p>
        </div>
      </div>

      <form className="form-grid" onSubmit={handleSubmit}>
        <label>
          Recipient
          <input
            name="recipient_name"
            onChange={handleChange}
            placeholder="Acme Vendor"
            required
            value={form.recipient_name}
          />
        </label>

        <label>
          Amount
          <input
            min="0.01"
            name="amount"
            onChange={handleChange}
            placeholder="125.50"
            required
            step="0.01"
            type="number"
            value={form.amount}
          />
        </label>

        <label>
          Type
          <select
            name="transaction_type"
            onChange={handleChange}
            value={form.transaction_type}
          >
            <option value="payment">Payment</option>
            <option value="transfer">Transfer</option>
            <option value="bill">Bill</option>
          </select>
        </label>

        <label>
          Reference
          <input
            name="reference"
            onChange={handleChange}
            placeholder="Invoice #1042"
            value={form.reference}
          />
        </label>

        {error ? <p className="form-error">{error}</p> : null}

        <button className="primary-button" disabled={submitting} type="submit">
          {submitting ? "Submitting..." : "Submit transaction"}
        </button>
      </form>
    </section>
  );
}
