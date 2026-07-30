defmodule Agency.Sale.ClockTest do
  use ExUnit.Case, async: true

  alias Agency.Sale.Clock

  test "the same exchange date lands on different cooling-off expiries per state" do
    exchanged_on = ~D[2026-10-02]

    assert Clock.add_business_days(exchanged_on, 5, :nsw) ==
             {~D[2026-10-12], ["Labour Day"]}

    assert Clock.add_business_days(exchanged_on, 3, :vic) == {~D[2026-10-07], []}

    assert Clock.add_business_days(exchanged_on, 5, :qld) ==
             {~D[2026-10-12], ["King's Birthday"]}
  end

  test "a span crossing only a weekend skips it without reporting a holiday" do
    assert Clock.add_business_days(~D[2026-02-06], 1, :nsw) == {~D[2026-02-09], []}
  end

  test "a span crossing Christmas and the observed Boxing Day reports both" do
    assert Clock.add_business_days(~D[2026-12-23], 2, :nsw) ==
             {~D[2026-12-29], ["Christmas Day", "Boxing Day observed"]}
  end

  test "a weekend is not a business day in any state" do
    refute Clock.business_day?(~D[2026-10-03], :nsw)
    refute Clock.business_day?(~D[2026-10-04], :vic)
  end

  test "a state-specific holiday is not a business day only in that state" do
    refute Clock.business_day?(~D[2026-11-03], :vic)
    assert Clock.business_day?(~D[2026-11-03], :nsw)
    assert Clock.business_day?(~D[2026-11-03], :qld)
  end
end
