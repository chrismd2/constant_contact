// Create contact page functionality
(function() {
  const form = document.getElementById('contact-form');
  const errorAlert = document.getElementById('error-alert');
  const errorMessage = document.getElementById('error-message');
  const successAlert = document.getElementById('success-alert');

  if (!form) return;

  form.addEventListener('submit', async function(e) {
    e.preventDefault();
    
    // Hide previous alerts
    if (errorAlert) errorAlert.classList.add('hidden');
    if (successAlert) successAlert.classList.add('hidden');

    // Get form data
    const formData = new FormData(form);
    const email = formData.get('email');
    const firstName = formData.get('first-name');
    const lastName = formData.get('last-name');
    const phone = formData.get('phone');
    const jobTitle = formData.get('job-title');
    const company = formData.get('company');
    const streetAddress = formData.get('street-address');
    const city = formData.get('city');
    const state = formData.get('state');
    const postalCode = formData.get('postal-code');
    const country = formData.get('country');
    const permissionToSend = formData.get('permission-to-send') || 'implicit';

    // Build contact data object
    const contactData = {
      email_address: {
        address: email,
        permission_to_send: permissionToSend
      },
      create_source: "Account"
    };

    // Add name if provided
    if (firstName || lastName) {
      if (firstName) contactData.first_name = firstName;
      if (lastName) contactData.last_name = lastName;
    }

    // Add phone if provided
    if (phone) {
      contactData.phone_number = {
        phone_number: phone
      };
    }

    // Add job title if provided
    if (jobTitle) {
      contactData.job_title = jobTitle;
    }

    // Add company if provided
    if (company) {
      contactData.company_name = company;
    }

    // Add address if any address fields are provided
    if (streetAddress || city || state || postalCode || country) {
      const address = {};
      if (streetAddress) address.street = streetAddress;
      if (city) address.city = city;
      if (state) address.state_code = state;
      if (postalCode) address.postal_code = postalCode;
      if (country) address.country_code = country;

      contactData.street_address = address;
    }

    try {
      // Disable submit button
      const submitBtn = form.querySelector('button[type="submit"]');
      const originalText = submitBtn.textContent;
      submitBtn.disabled = true;
      submitBtn.textContent = 'Creating...';

      const result = await apiCall('/contacts', {
        method: 'POST',
        body: JSON.stringify(contactData),
      });

      // Show success message
      if (successAlert) {
        successAlert.classList.remove('hidden');
      }

      // Reset form
      form.reset();

      // Scroll to top to show success message
      window.scrollTo({ top: 0, behavior: 'smooth' });

      // Re-enable submit button
      submitBtn.disabled = false;
      submitBtn.textContent = originalText;

    } catch (error) {
      // Show error message
      if (errorAlert) {
        errorAlert.classList.remove('hidden');
        if (errorMessage) {
          errorMessage.textContent = error.message;
        }
      }

      // Re-enable submit button
      const submitBtn = form.querySelector('button[type="submit"]');
      submitBtn.disabled = false;
      submitBtn.textContent = 'Create Contact';

      // Scroll to top to show error message
      window.scrollTo({ top: 0, behavior: 'smooth' });

      console.error('Error creating contact:', error);
    }
  });
})();
