defmodule Agency.Sale do
  @moduledoc """
  The agency's engagement with a vendor, from signing through to commission disbursed.

  Everything here is scoped underneath an agency agreement: the property it names, the
  attempts it spends, the buyers it keeps on register, and the commission each attempt earns.
  """

  use Ash.Domain

  resources do
    resource Agency.Sale.Property do
      define(:add_property, action: :add)
      define(:get_property, action: :by_id, args: [:id])
      define(:list_properties, action: :read)
    end

    resource Agency.Sale.AgencyAgreement do
      define(:sign_agreement, action: :sign)
      define(:sign_listing, action: :sign_listing)
      define(:hand_over_document, action: :hand_over_document, get_by: [:id], args: [:kind])
      define(:launch_campaign, action: :launch_campaign, get_by: [:id])
      define(:withdraw_listing, action: :withdraw_listing, get_by: [:id])
      define(:re_approach, action: :re_approach, get_by: [:id], args: [:buyer_id])
      define(:relaunch_campaign, action: :relaunch_campaign, get_by: [:id])
      define(:close_offers, action: :close_offers, get_by: [:id])
      define(:select_offer, action: :select_offer, get_by: [:id], args: [:offer_id])
      define(:sell_under_the_hammer, action: :sell_under_the_hammer, get_by: [:id])
      define(:pass_in, action: :pass_in, get_by: [:id])
      define(:rescind, action: :rescind, get_by: [:id], args: [:buyer_id])
      define(:resolve_inspection, action: :resolve_inspection, get_by: [:id], args: [:decision])
      define(:get_agreement, action: :by_id, args: [:id])
      define(:list_agreements, action: :read)
    end

    resource Agency.Sale.ComplianceDocument do
      define(:require_document, action: :require)
      define(:record_document_arrival, action: :arrive)
      define(:receive_document, action: :receive, get_by: [:id])
      define(:list_compliance_documents, action: :read)
    end

    resource Agency.Sale.SaleAttempt do
      define(:open_attempt, action: :open)
      define(:close_attempt, action: :close, get_by: [:id])
      define(:get_attempt, action: :by_id, args: [:id])

      define(:attempts_for_agreement,
        action: :for_agreement,
        args: [:agency_agreement_id]
      )

      define(:list_attempts, action: :read)
    end

    resource Agency.Sale.Buyer do
      define(:register_buyer, action: :register)
      define(:get_buyer, action: :by_id, args: [:id])
      define(:set_buyer_register_status, action: :set_register_status, get_by: [:id])

      define(:available_buyers,
        action: :available_for_agreement,
        args: [:agency_agreement_id]
      )

      define(:list_buyers, action: :read)
    end

    resource Agency.Sale.Offer do
      define(:make_offer, action: :make)
      define(:receive_offer, action: :receive)
      define(:set_offer_status, action: :set_status, get_by: [:id])
      define(:respond_to_offer, action: :respond, get_by: [:id], args: [:decision])
      define(:get_offer, action: :by_id, args: [:id])
      define(:offers_for_attempt, action: :for_attempt, args: [:sale_attempt_id])
      define(:live_offers_for_attempt, action: :live_for_attempt, args: [:sale_attempt_id])
      define(:list_offers, action: :read)
    end

    resource Agency.Sale.Contract do
      define(:exchange_contract, action: :exchange)
      define(:go_unconditional, action: :go_unconditional, get_by: [:id])
      define(:record_finance, action: :record_finance, get_by: [:id], args: [:decision])
      define(:record_title, action: :record_title, get_by: [:id], args: [:decision])
      define(:settle_contract, action: :settle, get_by: [:id])
      define(:buyer_defaults, action: :buyer_defaults, get_by: [:id])
      define(:contracts_for_attempt, action: :for_attempt, args: [:sale_attempt_id])
      define(:list_contracts, action: :read)
    end

    resource Agency.Sale.Condition do
      define(:impose_condition, action: :impose)
      define(:resolve_condition, action: :resolve, get_by: [:id])
      define(:conditions_for_contract, action: :for_contract, args: [:contract_id])
      define(:list_conditions, action: :read)
    end

    resource Agency.Sale.Deposit do
      define(:collect_deposit, action: :collect)
      define(:settle_deposit_status, action: :settle_status, get_by: [:id])
      define(:deposits_for_contract, action: :for_contract, args: [:contract_id])
      define(:list_deposits, action: :read)
    end

    resource Agency.Sale.Commission do
      define(:accrue_commission, action: :accrue)
      define(:disburse_commission, action: :disburse, get_by: [:id])
      define(:write_back_commission, action: :write_back, get_by: [:id])
      define(:commissions_for_attempt, action: :for_attempt, args: [:sale_attempt_id])
      define(:list_commissions, action: :read)
    end
  end
end
