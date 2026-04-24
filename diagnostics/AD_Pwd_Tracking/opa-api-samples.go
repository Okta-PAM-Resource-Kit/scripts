package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

// OPA API Sample Code for Active Directory Operations
// These samples demonstrate how to interact with OPA's AD-related API endpoints

const (
	baseURL  = "https://YOUR_ORG.pam.okta.com"
	teamName = "YOUR_TEAM"
)

// TokenResponse represents the OAuth2 token response from OPA
type TokenResponse struct {
	BearerToken string    `json:"bearer_token"`
	ExpiresAt   time.Time `json:"expires_at"`
	TeamName    string    `json:"team_name"`
}

// TokenRequest represents the request body for service_token endpoint
type tokenRequest struct {
	KeyID     string `json:"key_id"`
	KeySecret string `json:"key_secret"`
}

// ADConnection represents an Active Directory connection
type ADConnection struct {
	ID     string `json:"id"`
	Domain string `json:"domain"`
	Status string `json:"status"`
}

// ADConnectionsResponse represents the list response for AD connections
type ADConnectionsResponse struct {
	List []ADConnection `json:"list"`
}

// ADAccount represents an Active Directory account
type ADAccount struct {
	ID       string `json:"id"`
	Username string `json:"username"`
}

// ADAccountsResponse represents the list response for AD accounts
type ADAccountsResponse struct {
	List []ADAccount `json:"list"`
}

// ADAccountDetail represents detailed account information including rotation status
type ADAccountDetail struct {
	Account struct {
		ID                      string `json:"id"`
		Username                string `json:"username"`
		AccountType             string `json:"account_type"`
		AvailabilityStatus      string `json:"availability_status"`
		FirstName               string `json:"first_name"`
		LastName                string `json:"last_name"`
		Email                   string `json:"email"`
		DisplayName             string `json:"display_name"`
		SamAccountName          string `json:"sam_account_name"`
		BroughtUnderManagementAt string `json:"brought_under_management_at"`
		DistinguishedName       string `json:"distinguished_name"`
		SID                     string `json:"sid"`
	} `json:"account"`
	CheckoutDetails struct {
		CheckoutRequired             bool   `json:"checkout_required"`
		LastCheckedOutBy             string `json:"last_checked_out_by"`
		CurrentUserCheckoutExpiresAt string `json:"current_user_checkout_expires_at"`
	} `json:"checkout_details"`
	Rotation struct {
		LastPasswordChangeSuccessReportTimestamp string `json:"last_password_change_success_report_timestamp"`
		LastPasswordChangeSystemTimestamp        string `json:"last_password_change_system_timestamp"`
		LastPasswordChangeErrorReportTimestamp   string `json:"last_password_change_error_report_timestamp"`
		LastPasswordChangeErrorSystemTimestamp   string `json:"last_password_change_error_system_timestamp"`
		LastPasswordChangeErrorType              string `json:"last_password_change_error_type"`
		PasswordChangeSuccessCount               int    `json:"password_change_success_count"`
		PasswordChangeErrorCount                 int    `json:"password_change_error_count"`
		PasswordChangeErrorCountSinceLastSuccess int    `json:"password_change_error_count_since_last_success"`
	} `json:"rotation"`
}

// Client wraps HTTP client with auth
type Client struct {
	httpClient *http.Client
	baseURL    string
	teamName   string
	token      string
}

// NewClient creates a new OPA API client
func NewClient(baseURL, teamName string) *Client {
	return &Client{
		httpClient: &http.Client{Timeout: 30 * time.Second},
		baseURL:    baseURL,
		teamName:   teamName,
	}
}

// Authenticate exchanges key credentials for a bearer token
// POST /v1/teams/{team_name}/service_token
func (c *Client) Authenticate(ctx context.Context, keyID, keySecret string) error {
	url := fmt.Sprintf("%s/v1/teams/%s/service_token", c.baseURL, c.teamName)

	reqBody := tokenRequest{
		KeyID:     keyID,
		KeySecret: keySecret,
	}

	jsonBody, err := json.Marshal(reqBody)
	if err != nil {
		return fmt.Errorf("failed to marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(jsonBody))
	if err != nil {
		return fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("authentication failed (%d): %s", resp.StatusCode, string(body))
	}

	var tokenResp TokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&tokenResp); err != nil {
		return fmt.Errorf("failed to decode response: %w", err)
	}

	c.token = tokenResp.BearerToken
	return nil
}

// doRequest performs an authenticated API request
func (c *Client) doRequest(ctx context.Context, method, path string, body interface{}) ([]byte, error) {
	url := fmt.Sprintf("%s%s", c.baseURL, path)

	var bodyReader io.Reader
	if body != nil {
		jsonBody, err := json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal body: %w", err)
		}
		bodyReader = bytes.NewBuffer(jsonBody)
	}

	req, err := http.NewRequestWithContext(ctx, method, url, bodyReader)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.token))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to execute request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("request failed (%d): %s", resp.StatusCode, string(respBody))
	}

	return respBody, nil
}

// ListADConnections retrieves all AD connections for the team
// GET /v1/teams/{team_name}/connections/active_directory
func (c *Client) ListADConnections(ctx context.Context) ([]ADConnection, error) {
	path := fmt.Sprintf("/v1/teams/%s/connections/active_directory", c.teamName)

	respBody, err := c.doRequest(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}

	var resp ADConnectionsResponse
	if err := json.Unmarshal(respBody, &resp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return resp.List, nil
}

// ListADAccounts retrieves all AD accounts for a connection
// GET /v1/teams/{team_name}/active_directory/{ad_connection_id}/accounts
func (c *Client) ListADAccounts(ctx context.Context, connectionID string) ([]ADAccount, error) {
	path := fmt.Sprintf("/v1/teams/%s/active_directory/%s/accounts", c.teamName, connectionID)

	respBody, err := c.doRequest(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}

	var resp ADAccountsResponse
	if err := json.Unmarshal(respBody, &resp); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return resp.List, nil
}

// GetADAccountDetail retrieves detailed account info including rotation status
// GET /v1/teams/{team_name}/active_directory/{ad_connection_id}/accounts/{ad_account_id}
func (c *Client) GetADAccountDetail(ctx context.Context, connectionID, accountID string) (*ADAccountDetail, error) {
	path := fmt.Sprintf("/v1/teams/%s/active_directory/%s/accounts/%s", c.teamName, connectionID, accountID)

	respBody, err := c.doRequest(ctx, http.MethodGet, path, nil)
	if err != nil {
		return nil, err
	}

	var detail ADAccountDetail
	if err := json.Unmarshal(respBody, &detail); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return &detail, nil
}

// Example usage
func main() {
	ctx := context.Background()

	client := NewClient(baseURL, teamName)

	// Step 1: Authenticate
	err := client.Authenticate(ctx, "YOUR_KEY_ID", "YOUR_KEY_SECRET")
	if err != nil {
		fmt.Printf("Authentication failed: %v\n", err)
		return
	}
	fmt.Println("Authenticated successfully")

	// Step 2: List AD connections
	connections, err := client.ListADConnections(ctx)
	if err != nil {
		fmt.Printf("Failed to list connections: %v\n", err)
		return
	}

	fmt.Printf("Found %d AD connections:\n", len(connections))
	for _, conn := range connections {
		fmt.Printf("  - %s (ID: %s, Status: %s)\n", conn.Domain, conn.ID, conn.Status)
	}

	if len(connections) == 0 {
		return
	}

	// Step 3: List accounts for the first connection
	connectionID := connections[0].ID
	accounts, err := client.ListADAccounts(ctx, connectionID)
	if err != nil {
		fmt.Printf("Failed to list accounts: %v\n", err)
		return
	}

	fmt.Printf("\nFound %d managed accounts:\n", len(accounts))
	for _, acct := range accounts {
		fmt.Printf("  - %s (ID: %s)\n", acct.Username, acct.ID)
	}

	// Step 4: Get rotation details for first account
	if len(accounts) > 0 {
		detail, err := client.GetADAccountDetail(ctx, connectionID, accounts[0].ID)
		if err != nil {
			fmt.Printf("Failed to get account detail: %v\n", err)
			return
		}

		fmt.Printf("\nRotation details for %s:\n", detail.Account.Username)
		fmt.Printf("  Last successful rotation: %s\n", detail.Rotation.LastPasswordChangeSuccessReportTimestamp)
		fmt.Printf("  Success count: %d\n", detail.Rotation.PasswordChangeSuccessCount)
		fmt.Printf("  Error count: %d\n", detail.Rotation.PasswordChangeErrorCount)
	}
}
