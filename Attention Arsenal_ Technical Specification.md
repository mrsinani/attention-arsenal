# Attention Arsenal: Technical Specification

## 1. Introduction

This document outlines the technical specifications for 'Attention Arsenal', an iOS application designed as an alternative to the native Reminders app. The primary focus of Attention Arsenal is to help users manage short-term, easily forgotten tasks through a minimalist interface and persistent, customizable notifications. The application will be developed natively for iOS using SwiftUI.

## 2. Core Features

### 2.1 Arsenal Management

Users will be able to create, view, edit, and complete 'arsenals' (todo items). Each arsenal will include essential information to facilitate task management and notification.

#### 2.1.1 Arsenal Creation

When creating a new arsenal, users will provide the following details:

*   **Title:** A concise name for the arsenal (e.g., "Do Laundry", "Finish Math Homework").
*   **Description (Optional):** A more detailed explanation of the task.
*   **Due Date (Optional):** A specific date and time by which the arsenal should be completed.
*   **Notification Repetition Interval:** Users will select how frequently they wish to be reminded of the arsenal. Options will include predefined intervals such as "every 5 minutes", "every 30 minutes", "every hour", etc. This will be a customizable setting per arsenal.

#### 2.1.2 Arsenal Completion

Arsenals can be marked as complete using a checkbox mechanism, similar to the native iOS Reminders app. Upon completion, the arsenal will be visually distinguished (e.g., struck through or moved to a 'completed' section) but will remain accessible for review.

#### 2.1.3 Arsenal Editing and Deletion

Users will have the ability to edit existing arsenals to update their details, including title, description, due date, and notification repetition interval. Arsenals can also be deleted permanently.

### 2.2 Notification System

The application will leverage native iOS notifications to provide persistent reminders for active arsenals. The key aspect of this system is the customizable and repeated notification delivery.

#### 2.2.1 Repeated Notifications

Notifications for each active arsenal will repeat at the interval specified by the user during arsenal creation or editing. This ensures that users are consistently reminded of tasks until they are marked as complete.

#### 2.2.2 Notification Content

Each notification will primarily display the arsenal's title. The description may be included in the notification body if space permits or as a secondary detail.

#### 2.2.3 Notification Customization

Users will be able to customize the repetition interval for each individual arsenal. The app will offer a selection of common intervals, and potentially allow for custom interval input in future iterations.

## 3. User Interface (UI) / User Experience (UX)

The UI/UX design will prioritize minimalism and ease of use, specifically catering to the needs of the ADHD community by reducing visual clutter and cognitive load. The app will feature a clean, intuitive interface built with SwiftUI.

#### 3.1 Overall Design Philosophy

The design will be minimalist, focusing on essential information and clear calls to action. Colors will be subtle, and typography will be highly legible. The goal is to create a calm and focused environment for task management.

#### 3.2 Key Screens/Views

*   **Active Arsenals List View:** The main screen will display a clear, uncluttered list of all active (incomplete) arsenals. Each item will prominently feature the arsenal's title and a checkbox for completion.
*   **Arsenal Detail/Edit View:** Tapping on an arsenal will lead to a detail view where users can see all information, edit fields, and manage notification settings.
*   **New Arsenal Creation View:** A dedicated view for inputting new arsenal details.

#### 3.3 Navigation

Navigation will be straightforward and intuitive, likely utilizing standard iOS navigation patterns (e.g., navigation stacks, sheets) to ensure a familiar user experience.

## 4. Technical Architecture

### 4.1 Technology Stack

*   **Programming Language:** Swift
*   **UI Framework:** SwiftUI
*   **Notification Framework:** UserNotifications (native iOS notifications)

### 4.2 Data Persistence

For data persistence, the application will store arsenal data locally on the device. Options for implementation include:

*   **Core Data:** Apple's native persistence framework, offering robust object graph management and performance for structured data.
*   **UserDefaults:** Suitable for storing simple user preferences and small amounts of data, but less ideal for complex data models like arsenals.
*   **Realm:** A third-party mobile database that is often praised for its ease of use and performance.

Given the structured nature of arsenals (title, description, due date, notification settings), **Core Data** is the recommended choice for its scalability and integration with the Apple ecosystem. It provides a powerful and efficient way to manage the application's data model.

### 4.3 Notification Implementation

Native iOS notifications will be implemented using the `UserNotifications` framework. This will involve:

*   Requesting user permission for notifications.
*   Scheduling local notifications with custom content and triggers.
*   Managing repeated notifications based on the user-defined interval for each arsenal.
*   Handling notification interactions (e.g., opening the app from a notification).

## 5. Future Considerations (Out of Scope for Initial Release)

*   Categorization or tagging of arsenals.
*   Progress tracking and statistics.
*   Integration with Siri Shortcuts or Widgets.
*   Cloud synchronization for data backup and multi-device access.
*   Custom notification sounds.

## 6. Conclusion

This specification provides a foundational understanding of the 'Attention Arsenal' iOS application. By focusing on a minimalist design, robust arsenal management, and a persistent notification system, the app aims to provide a highly effective tool for managing short-term tasks, particularly for individuals who benefit from consistent reminders. The use of native iOS technologies ensures optimal performance and a seamless user experience.

