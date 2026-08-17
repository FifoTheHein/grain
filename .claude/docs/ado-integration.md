# ADO Integration Details

See `work-item-search.md` for the WIQL-backed picker that finds a work item
without knowing its number.

When a time entry links to an ADO work item, the external reference ID stored in Harvest uses the composite format: `AzureDevOps_{projectGuid}_{workItemType}_{numericId}`. The project GUID is fetched from ADO and cached. The app degrades gracefully if the GUID is unavailable (falls back to the numeric ID alone) or if no ADO PAT is configured.
