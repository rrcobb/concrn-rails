class DispatchMessanger

  def initialize(responder)
    @responder = responder
    @dispatch  = responder.dispatches.latest
    @report    = @dispatch.report unless @dispatch.nil?
  end

  def respond(body)
    feedback = true
    if @responder.on_shift? && body[/break/i]
      @responder.shifts.end!('sms') && feedback = false if non_breaktime
      status = 'rejected' if @dispatch && @dispatch.pending?
    elsif !@responder.on_shift? && body[/on/i]
      @responder.shifts.start!('sms') && feedback = false
    elsif @dispatch.pending? && body[/no/i]
      status = 'rejected'
    elsif @dispatch.accepted? && body[/done/i]
      status = 'completed'
    elsif !@dispatch.accepted? && !@dispatch.completed?
      status = 'accepted'
    end
    @dispatch.update_attributes!(status: status)
    give_feedback(body) if feedback
  end

  def accept!
    @dispatch.update_attribute(:accepted_at, Time.now)
    @report.logs.create!(author: @responder, body: "*** Accepted the dispatch ***")
    acknowledge_acceptance
    primary_responder
    notify_reporter
  end

  def complete!
    @report.complete!
    thank_responder
    thank_reporter
  end

  def pending!
    responder_synopses.each { |snippet| Telephony.send(snippet, @responder.phone) }
  end

  def reject!
    acknowledge_rejection
  end

private

  def acknowledge_acceptance
    Telephony.send("You have been assigned to an incident at #{@report.address}.", @responder.phone)
  end

  def acknowledge_rejection
    Telephony.send("You have been removed from this incident at #{@report.address}. You are now available to be dispatched.", @responder.phone)
  end

  def give_feedback(body)
    @report.logs.create!(author: @responder, body: body)
  end

  def non_breaktime
    @dispatch.nil? || @dispatch.completed? || @dispatch.pending?
  end

  def notify_reporter
    Telephony.send(reporter_synopsis, @report.phone)
  end

  def primary_responder
    if @report.accepted_dispatches.count > 1 && primary = @report.accepted_dispatches.first.responder
      Telephony.send("The primary responder for this report is: #{primary.name} – #{primary.phone}", @responder.phone)
    end
  end


  def reporter_synopsis
    if @report.accepted_dispatches.count > 1 && primary = @report.accepted_dispatches.first.responder
      "#{@responder.name} - #{@responder.phone} is on the way to help #{primary.name}."
    else
      "INCIDENT RESPONSE: #{@responder.name} is on the way. #{@responder.phone}"
    end
  end

  def responder_synopses
    [
      @report.address,
      "Reporter: #{[@report.name, @report.phone].delete_blank * ', '}",
      "#{[@report.race, @report.gender, @report.age].delete_blank * '/'}",
      @report.setting,
      @report.nature
    ].delete_blank
  end

  def thank_responder
    Telephony.send("The report is now completed, thanks for your help! You are now available to be dispatched.", @responder.phone)
  end

  def thank_reporter
    Telephony.send("Report resolved, thanks for being concrned!", @report.phone)
  end
end
