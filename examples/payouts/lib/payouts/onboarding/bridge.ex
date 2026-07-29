defmodule Payouts.Onboarding.Bridge do
  @moduledoc """
  Bridge's KYC: open the account, accept the terms, open a submission, send the profile and the
  questionnaire, upload every document Bridge asks for, then close the submission.

  Which documents Bridge wants is Bridge's business, so the list is read from the provider rather
  than passed in, and each upload is its own checkpoint. A run that stops part way resumes
  into the submission already open.

  Nothing here declares an undo. Onboarding is carried forward: a submission Bridge has partly
  decided is the thing a resumed run needs, and tearing the account down would cost the
  customer every document they have already sent.
  """

  use Reactor, extensions: [Magma.Dsl]

  alias Payouts.Onboarding.Bridge.Steps

  magma do
    queue(:onboarding)
    retention(:timer.hours(24 * 30))
  end

  input(:onboarding_id)

  step :onboarding, Steps.Load do
    argument(:onboarding_id, input(:onboarding_id))
  end

  step :account, Steps.CreateAccount do
    argument(:onboarding, result(:onboarding))
  end

  step :terms, Steps.AcceptTerms do
    argument(:account, result(:account))
  end

  step :submission, Steps.OpenSubmission do
    argument(:account, result(:account))
    wait_for(:terms)
  end

  step :profile, Steps.SubmitProfile do
    argument(:submission, result(:submission))
    argument(:onboarding, result(:onboarding))
  end

  step :questionnaire, Steps.SubmitQuestionnaire do
    argument(:submission, result(:submission))
    wait_for(:profile)
  end

  step :required_documents, Steps.RequiredDocuments do
    wait_for(:questionnaire)
  end

  map :documents do
    source(result(:required_documents))

    step :upload, Steps.UploadDocument do
      argument(:kind, element(:documents))
      argument(:submission, result(:submission))
    end

    return(:upload)
  end

  step :decision, Steps.CloseSubmission do
    argument(:submission, result(:submission))
    argument(:onboarding, result(:onboarding))
    argument(:account, result(:account))
    wait_for(:documents)
  end

  return(:decision)
end
