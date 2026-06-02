/**
 * Post-install handler for the googleMapsMCP managed package.
 *
 * Responsibilities (each step is idempotent — re-runs and upgrades skip
 * work that is already in place):
 *   1. Assign the packaged permission set (`googleMapsMCP_Perm_Set`) to
 *      the user who initiated the install.
 *   2. Resolve the Platform Integration User and assign the same
 *      permission set to that user so server-to-server MCP callouts have
 *      the External Credential principal access they need.
 *   3. Verify the packaged permission set actually carries read access on
 *      the `UserExternalCredential` object. If the deployed permission
 *      set is missing that grant (e.g. it was stripped during a
 *      subscriber-side install), create a fallback permission set with
 *      that single grant and assign it to both users.
 *
 * Implemented as `global without sharing` because Salesforce requires the
 * InstallHandler entry point to be `global` and the work performed here
 * must succeed regardless of the installing user's sharing rules.
 */
global without sharing class GoogleMapsMCPPostInstall implements InstallHandler {
  @TestVisible
  private static String packagePermSetName = 'googleMapsMCP_Perm_Set';

  @TestVisible
  private static String fallbackPermSetName = 'googleMapsMCP_UEC_Access';

  @TestVisible
  private static String fallbackPermSetLabel = 'googleMapsMCP - UserExternalCredential Read (Post-Install)';

  /**
   * The Platform Integration User follows a deterministic naming convention
   * scoped to each org:
   *   Username = `cloud@{18-character org id, lowercased}`
   *   Email    = `noreply@{18-character org id, lowercased}`
   * Matching on this convention avoids the false positives we would hit by
   * filtering on a `Name LIKE 'Platform%'` style query when a subscriber org
   * happens to have other users whose names start with "Platform".
   */
  @TestVisible
  private static final String INTEGRATION_USERNAME_PREFIX = 'cloud@';

  @TestVisible
  private static final String INTEGRATION_EMAIL_PREFIX = 'noreply@';

  /** Optional overrides used by tests to avoid colliding with the real
   *  Platform Integration User (whose Username is globally unique). */
  @TestVisible
  private static String integrationUsernameOverride;

  @TestVisible
  private static String integrationEmailOverride;

  private static final String UEC_SOBJECT = 'UserExternalCredential';

  global void onInstall(InstallContext context) {
    Set<Id> userIds = collectTargetUsers(context.installerId());

    Id packagePermSetId = findPermissionSetIdByName(packagePermSetName);
    if (packagePermSetId != null) {
      assignPermissionSet(packagePermSetId, userIds);
    }

    Boolean hasUecRead =
      packagePermSetId != null &&
      permissionSetHasObjectRead(packagePermSetId, UEC_SOBJECT);

    if (!hasUecRead) {
      Id fallbackId = ensureFallbackPermissionSet();
      if (fallbackId != null) {
        assignPermissionSet(fallbackId, userIds);
      }
    }
  }

  @TestVisible
  private Set<Id> collectTargetUsers(Id installerId) {
    Set<Id> users = new Set<Id>();
    if (installerId != null) {
      users.add(installerId);
    }
    Id integrationUserId = findPlatformIntegrationUserId();
    if (integrationUserId != null) {
      users.add(integrationUserId);
    }
    return users;
  }

  @TestVisible
  private Id findPlatformIntegrationUserId() {
    String expectedUsername = getIntegrationUsername();
    String expectedEmail = getIntegrationEmail();

    List<User> byUsername = [
      SELECT Id
      FROM User
      WHERE IsActive = TRUE AND Username = :expectedUsername
      LIMIT 1
    ];
    if (!byUsername.isEmpty()) {
      return byUsername[0].Id;
    }

    List<User> byEmail = [
      SELECT Id
      FROM User
      WHERE IsActive = TRUE AND Email = :expectedEmail
      LIMIT 1
    ];
    return byEmail.isEmpty() ? null : byEmail[0].Id;
  }

  @TestVisible
  private static String getIntegrationUsername() {
    if (integrationUsernameOverride != null) {
      return integrationUsernameOverride;
    }
    return INTEGRATION_USERNAME_PREFIX + getOrgId18Lower();
  }

  @TestVisible
  private static String getIntegrationEmail() {
    if (integrationEmailOverride != null) {
      return integrationEmailOverride;
    }
    return INTEGRATION_EMAIL_PREFIX + getOrgId18Lower();
  }

  @TestVisible
  private static String getOrgId18Lower() {
    // Casting through Id guarantees the 18-character form even if the
    // underlying API returned a 15-character id.
    Id orgId = UserInfo.getOrganizationId();
    return String.valueOf(orgId).toLowerCase();
  }

  @TestVisible
  private Id findPermissionSetIdByName(String developerName) {
    List<PermissionSet> sets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = :developerName
      LIMIT 1
    ];
    return sets.isEmpty() ? null : sets[0].Id;
  }

  @TestVisible
  private Boolean permissionSetHasObjectRead(Id permSetId, String sobjectType) {
    List<ObjectPermissions> perms = [
      SELECT Id
      FROM ObjectPermissions
      WHERE
        ParentId = :permSetId
        AND SobjectType = :sobjectType
        AND PermissionsRead = TRUE
      LIMIT 1
    ];
    return !perms.isEmpty();
  }

  @TestVisible
  private Id ensureFallbackPermissionSet() {
    Id existingId = findPermissionSetIdByName(fallbackPermSetName);
    if (existingId != null) {
      if (!permissionSetHasObjectRead(existingId, UEC_SOBJECT)) {
        insertUecReadPermission(existingId);
      }
      return existingId;
    }

    PermissionSet ps = new PermissionSet(
      Name = fallbackPermSetName,
      Label = fallbackPermSetLabel,
      Description = 'Auto-generated by googleMapsMCP post-install to ensure UserExternalCredential read access when the packaged permission set is missing it.'
    );
    Database.SaveResult psResult = Database.insert(ps, false);
    if (!psResult.isSuccess()) {
      return null;
    }

    insertUecReadPermission(ps.Id);
    return ps.Id;
  }

  private void insertUecReadPermission(Id permSetId) {
    ObjectPermissions op = new ObjectPermissions(
      ParentId = permSetId,
      SobjectType = UEC_SOBJECT,
      PermissionsRead = true,
      PermissionsCreate = false,
      PermissionsEdit = false,
      PermissionsDelete = false,
      PermissionsViewAllRecords = false,
      PermissionsModifyAllRecords = false
    );
    Database.insert(op, false);
  }

  @TestVisible
  private void assignPermissionSet(Id permSetId, Set<Id> userIds) {
    if (permSetId == null || userIds == null || userIds.isEmpty()) {
      return;
    }

    Set<Id> alreadyAssigned = new Set<Id>();
    for (PermissionSetAssignment psa : [
      SELECT AssigneeId
      FROM PermissionSetAssignment
      WHERE PermissionSetId = :permSetId AND AssigneeId IN :userIds
    ]) {
      alreadyAssigned.add(psa.AssigneeId);
    }

    List<PermissionSetAssignment> toCreate = new List<PermissionSetAssignment>();
    for (Id uid : userIds) {
      if (!alreadyAssigned.contains(uid)) {
        toCreate.add(
          new PermissionSetAssignment(
            AssigneeId = uid,
            PermissionSetId = permSetId
          )
        );
      }
    }

    if (!toCreate.isEmpty()) {
      Database.insert(toCreate, false);
    }
  }
}
