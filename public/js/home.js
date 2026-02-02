// Home page functionality
(function() {
  const refreshBtn = document.getElementById('refresh-oauth-btn');
  const oauthStatus = document.getElementById('oauth-status');

  if (!refreshBtn) return;

  refreshBtn.addEventListener('click', async function() {
    const originalText = refreshBtn.textContent;
    refreshBtn.disabled = true;
    refreshBtn.textContent = 'Refreshing...';
    
    if (oauthStatus) {
      oauthStatus.innerHTML = '';
      oauthStatus.className = 'mt-4 text-sm';
    }

    try {
      // Use API_BASE from app.js (must be loaded before this script)
      const apiBase = window.API_BASE || '/';
      const url = apiBase === '/' ? '/oauth/refresh' : apiBase + '/oauth/refresh';
      
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: JSON.stringify({}),
      });

      const data = await response.json();

      if (!response.ok) {
        // Check if re-authorization is required
        if (data.error?.requires_reauth && data.error?.authorization_url) {
          if (oauthStatus) {
            oauthStatus.className = 'mt-4 text-sm text-yellow-600 dark:text-yellow-400';
            oauthStatus.innerHTML = '⚠ Refresh token expired. <a href="' + data.error.authorization_url + '" class="underline font-semibold">Click here to re-authorize</a>';
          }
          // Optionally auto-redirect
          if (confirm('Your refresh token has expired. Would you like to re-authorize now?')) {
            window.location.href = data.error.authorization_url;
          }
        } else {
          throw new Error(data.error?.message || 'Token refresh failed');
        }
      } else {
        if (oauthStatus) {
          oauthStatus.className = 'mt-4 text-sm text-green-600 dark:text-green-400';
          oauthStatus.textContent = '✓ Token refreshed successfully!';
        }
      }
    } catch (error) {
      if (oauthStatus) {
        oauthStatus.className = 'mt-4 text-sm text-red-600 dark:text-red-400';
        oauthStatus.textContent = '✗ Error: ' + error.message;
      }
      console.error('Error refreshing token:', error);
    } finally {
      refreshBtn.disabled = false;
      refreshBtn.textContent = originalText;
    }
  });
})();
