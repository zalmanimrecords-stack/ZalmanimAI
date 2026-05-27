# Flutter UI TODO

Decision: keep the admin and artist portal in Flutter for now. Do not start a React rewrite unless a small proof-of-concept proves a clear advantage.

## Goals

- Reduce admin UI complexity without changing backend behavior.
- Keep the current FastAPI contracts stable.
- Improve dashboard maintainability, tables, forms, routing, and visual consistency.
- Make future React migration optional, not urgent.

## Near-Term Tasks

- [ ] Split `apps/client/lib/features/admin/admin_dashboard_page.dart` into smaller tab, layout, and state components.
- [ ] Move reusable admin UI patterns into focused widgets under `apps/client/lib/features/admin/widgets/`.
- [ ] Evaluate `data_table_2` for dense admin tables that need better scrolling, sizing, and sticky headers.
- [ ] Standardize table controls: search, filtering, sorting, refresh, empty states, loading states, and error states.
- [ ] Review admin dialogs and extract shared form field, validation, confirmation, and submit-state patterns.
- [ ] Keep API calls in the existing client layer instead of calling HTTP directly from widgets.
- [ ] Add or update focused Flutter tests before changing high-risk tabs.

## Candidate Flutter Packages

- `data_table_2`: improved Material-style tables.
- `go_router`: route and shell organization if navigation keeps growing.
- `fl_chart`: dashboard charts if reporting widgets expand.

## First Refactor Candidates

- [ ] Admin dashboard shell and navigation.
- [ ] Artists tab.
- [ ] Demos tab and demo submission dialogs.
- [ ] Campaigns section and campaign forms.
- [ ] Pending releases tab.
- [ ] Settings and mail settings screens.

## Validation Checklist

- [ ] Run `flutter analyze` in `apps/client`.
- [ ] Run `flutter test` in `apps/client`.
- [ ] Run `flutter analyze` in `apps/artist_portal` if shared patterns are touched.
- [ ] Run `flutter test` in `apps/artist_portal` if shared patterns are touched.
- [ ] Smoke test admin login and the changed tabs in the browser.

## React Revisit Criteria

Reconsider a React dashboard framework only if at least one of these becomes true:

- Flutter web blocks a required user experience or deployment need.
- Admin dashboard development remains slow after the Flutter refactor.
- A React-admin or Refine proof-of-concept reproduces a real tab faster with less custom code.
- The product becomes web-only and no longer benefits from Flutter's shared app model.
