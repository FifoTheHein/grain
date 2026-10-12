/// One concrete occurrence of a calendar event, read from an ICS feed.
///
/// Recurring series are already expanded by the parser, so every
/// [CalendarEvent] is a single meeting with a real start and end. Pure Dart —
/// no Flutter — so the import pipeline can be unit tested directly.
library;

class CalendarEvent {
  /// The ICS `UID`. Shared by every occurrence of a recurring series.
  final String uid;
  final String summary;

  /// Start and end as UTC instants.
  final DateTime start;
  final DateTime end;

  /// `STATUS` upper-cased: `CONFIRMED`, `TENTATIVE`, `CANCELLED`.
  final String? status;

  /// Outlook's `X-MICROSOFT-CDO-BUSYSTATUS`: `BUSY`, `FREE`, `TENTATIVE`,
  /// `OOF`.
  final String? busyStatus;

  /// `TRANSP`: `OPAQUE` or `TRANSPARENT` (shows as free).
  final String? transparency;

  /// `CLASS`: `PUBLIC`, `PRIVATE`, `CONFIDENTIAL`.
  final String? classification;

  final String? location;
  final String? description;

  /// Organizer display name and address, when the feed carries them. Outlook's
  /// published feeds strip both, so rules cannot rely on them there.
  final String? organizerName;
  final String? organizerEmail;

  /// The occurrence this event stands for in its series — the generated start
  /// for an expanded occurrence, or `RECURRENCE-ID` for an override. Null for a
  /// one-off meeting. It stays put when an override moves the meeting, which
  /// is what makes it the stable half of the dedup key.
  final DateTime? occurrence;

  const CalendarEvent({
    required this.uid,
    required this.summary,
    required this.start,
    required this.end,
    this.status,
    this.busyStatus,
    this.transparency,
    this.classification,
    this.location,
    this.description,
    this.organizerName,
    this.organizerEmail,
    this.occurrence,
  });

  Duration get duration => end.difference(start);

  CalendarEvent copyWith({
    DateTime? start,
    DateTime? end,
    DateTime? occurrence,
  }) =>
      CalendarEvent(
        uid: uid,
        summary: summary,
        start: start ?? this.start,
        end: end ?? this.end,
        status: status,
        busyStatus: busyStatus,
        transparency: transparency,
        classification: classification,
        location: location,
        description: description,
        organizerName: organizerName,
        organizerEmail: organizerEmail,
        occurrence: occurrence ?? this.occurrence,
      );

  @override
  String toString() => 'CalendarEvent($summary, $start → $end)';
}
