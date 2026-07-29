defmodule Payouts.Offramp do
  @moduledoc """
  Customers, their balances, and the transfers that move money out.

  Every way in is a code interface on this domain. The ones that take an id rather than a
  record load it themselves, so nothing is read only to be handed straight back.
  """

  use Ash.Domain

  resources do
    resource Payouts.Offramp.Customer do
      define(:open_customer, action: :open, args: [:name, :opening_balance_cents])

      define(:get_customer,
        action: :read,
        get_by: [:id],
        default_options: [load: [:balance_cents]]
      )

      define(:list_customers, action: :read, default_options: [load: [:balance_cents]])
      define(:customer_standing, action: :with_standing)
    end

    resource Payouts.Offramp.Transfer do
      define(:request_payout, action: :request)
      define(:start_payout, action: :request_payout)
      define(:get_transfer, action: :read, get_by: [:id])
      define(:transfer_feed, action: :feed)
      define(:payout, action: :payout, args: [:id])
      define(:set_transfer_status, action: :set_status, get_by: [:id])

      define(:approve_quote, action: :approve_quote, args: [:transfer_id])
      define(:deliver_settlement, action: :deliver_settlement, args: [:transfer_id, :outcome])
      define(:resume_payout, action: :resume_payout, args: [:transfer_id])
      define(:cancel_payout, action: :cancel_payout, args: [:transfer_id])
    end

    resource Payouts.Offramp.Onboarding do
      define(:begin_onboarding, action: :begin)
      define(:onboard, action: :start_kyc, args: [:customer_id, :destination_currency])
      define(:get_onboarding, action: :read, get_by: [:id])
      define(:record_onboarding_progress, action: :record_progress, get_by: [:id])

      define(:onboarding_for_rail,
        action: :for_rail,
        args: [:customer_id, :destination_currency]
      )
    end

    resource Payouts.Offramp.Beneficiary do
      define(:record_beneficiary, action: :record)
      define(:register_beneficiary, action: :register)
      define(:get_beneficiary, action: :read, get_by: [:id])
      define(:attach_beneficiary_ref, action: :attach_ref, get_by: [:id])
      define(:release_beneficiary_ref, action: :release_ref, get_by: [:id])

      define(:beneficiary_for_rail,
        action: :for_rail,
        args: [:customer_id, :destination_currency]
      )
    end

    resource Payouts.Offramp.LedgerEntry do
      define(:ledger_entries, action: :read)
      define(:ledger_entries_for_transfer, action: :for_transfer, args: [:transfer_id])
      define(:post_ledger_entry, action: :post)
    end
  end
end
